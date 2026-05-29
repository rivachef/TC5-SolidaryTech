#!/bin/bash
###############################################################################
# update-aws-credentials.sh
#
# Renova AWS credentials nos K8s Secrets do donation-service e volunteer-service.
# Necessario a cada nova sessao AWS Academy (4h), pois AWS Academy nao permite
# IRSA (iam:CreateOpenIDConnectProvider negado) e usamos creds via Secret.
#
# Apos atualizar, faz rollout restart dos deployments para pegar as novas envs.
#
# Uso:
#   # Atualize ~/.aws/credentials com creds frescas do Academy, depois:
#   ./scripts/update-aws-credentials.sh
###############################################################################
set -e
set -o pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $1"; }

# AWS creds (env vars OU aws configure)
if [ -z "$AWS_ACCESS_KEY_ID" ]; then
    AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id 2>/dev/null || echo "")
fi
if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key 2>/dev/null || echo "")
fi
if [ -z "$AWS_SESSION_TOKEN" ]; then
    AWS_SESSION_TOKEN=$(aws configure get aws_session_token 2>/dev/null || echo "")
fi

if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    log_err "Credenciais AWS nao encontradas (env vars nem aws configure)."
    exit 1
fi

# Valida que as creds funcionam (Academy ativo)
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    log_err "Credenciais AWS invalidas/expiradas. Renove no Academy."
    exit 1
fi

log_ok "AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID:0:12}..."

# ===== donation-service-secret =====
log_info "Atualizando donation-service-secret..."
# Preservar valores nao-AWS (DATABASE_URL e AWS_SQS_URL)
DATABASE_URL=$(kubectl get secret donation-service-secret -n solidarytech -o jsonpath='{.data.DATABASE_URL}' | base64 -d)
AWS_SQS_URL=$(kubectl get secret donation-service-secret -n solidarytech -o jsonpath='{.data.AWS_SQS_URL}' | base64 -d)

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: donation-service-secret
  namespace: solidarytech
type: Opaque
stringData:
  DATABASE_URL: "$DATABASE_URL"
  AWS_SQS_URL: "$AWS_SQS_URL"
  AWS_ACCESS_KEY_ID: "$AWS_ACCESS_KEY_ID"
  AWS_SECRET_ACCESS_KEY: "$AWS_SECRET_ACCESS_KEY"
  AWS_SESSION_TOKEN: "$AWS_SESSION_TOKEN"
EOF
log_ok "donation-service-secret atualizado"

# ===== volunteer-service-secret =====
log_info "Atualizando volunteer-service-secret..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: volunteer-service-secret
  namespace: solidarytech
type: Opaque
stringData:
  AWS_ACCESS_KEY_ID: "$AWS_ACCESS_KEY_ID"
  AWS_SECRET_ACCESS_KEY: "$AWS_SECRET_ACCESS_KEY"
  AWS_SESSION_TOKEN: "$AWS_SESSION_TOKEN"
EOF
log_ok "volunteer-service-secret atualizado"

# Restart pods para pegar nova env
log_info "Restartando deployments..."
kubectl rollout restart deployment/donation-service -n solidarytech 2>/dev/null || true
kubectl rollout restart deployment/volunteer-service -n solidarytech 2>/dev/null || true

log_ok "Credenciais renovadas. Aguarde pods reiniciarem:"
echo "  kubectl get pods -n solidarytech -w"
