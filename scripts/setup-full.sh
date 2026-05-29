#!/bin/bash
###############################################################################
# setup-full.sh
#
# Script master que orquestra o setup do ambiente SolidaryTech FASE 5.
# EVOLUTIVO: cresce a cada sprint do hackathon.
#
# Sprint 2 (DONE):    bootstrap backend + terraform apply + kubeconfig
# Sprint 3 (DONE):    CI/CD push de imagens pro ECR (via GitHub Actions)
# Sprint 4 (atual):   + build/push 1a imagem + ArgoCD + GitOps + NGINX Ingress
# Sprint 5 (futuro):  + Monitoring Stack (Prometheus + Loki + Grafana + OTel)
# Sprint 6 (futuro):  + Velero + DR drill
#
# Uso:
#   export AWS_ACCESS_KEY_ID=...
#   export AWS_SECRET_ACCESS_KEY=...
#   export AWS_SESSION_TOKEN=...
#   ./scripts/setup-full.sh [--auto-approve]
###############################################################################
set -e
set -o pipefail  # garante que erro em pipeline propaga (evita `| tee` mascarar exit code)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_DIR="$PROJECT_DIR/terraform/environments/primary"

AUTO_APPROVE=""
if [ "$1" = "--auto-approve" ]; then
    AUTO_APPROVE="-auto-approve"
fi

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "============================================"
echo "  SolidaryTech - Setup Completo (Sprint 2)"
echo "============================================"
echo ""

###############################################################################
# Step 0: Verificacoes iniciais
###############################################################################
log_info "[0/5] Verificando pre-requisitos..."

# AWS creds (suporta env vars OU aws configure)
if [ -z "$AWS_ACCESS_KEY_ID" ]; then
    AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id 2>/dev/null || echo "")
fi
if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key 2>/dev/null || echo "")
fi

if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    log_error "Credenciais AWS nao encontradas (nem em env vars, nem em aws configure)."
    exit 1
fi

if ! aws sts get-caller-identity > /dev/null 2>&1; then
    log_error "Credenciais AWS invalidas ou expiradas."
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
log_ok "AWS Account: $ACCOUNT_ID"
log_ok "AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID:0:12}..."

# Ferramentas
for tool in terraform kubectl aws; do
    if ! command -v "$tool" > /dev/null 2>&1; then
        log_error "Ferramenta nao encontrada: $tool"
        exit 1
    fi
done
log_ok "Ferramentas: terraform, kubectl, aws"

# terraform.tfvars — auto-gerar se nao existir
if [ ! -f "$ENV_DIR/terraform.tfvars" ]; then
    log_warn "terraform.tfvars nao encontrado. Gerando automaticamente..."
    cp "$ENV_DIR/terraform.tfvars.example" "$ENV_DIR/terraform.tfvars"

    # Substituir lab_role_arn com ACCOUNT_ID real (AWS Academy padrao)
    sed -i.bak "s|SEU_ACCOUNT_ID|${ACCOUNT_ID}|g" "$ENV_DIR/terraform.tfvars"
    rm -f "$ENV_DIR/terraform.tfvars.bak"

    # Gerar db_password aleatorio (24 chars alfanumericos)
    DB_PASS=$(openssl rand -base64 36 | tr -dc 'a-zA-Z0-9' | head -c 24)
    sed -i.bak "s|TROQUE_AQUI_DEV_PASSWORD|${DB_PASS}|g" "$ENV_DIR/terraform.tfvars"
    rm -f "$ENV_DIR/terraform.tfvars.bak"

    log_ok "terraform.tfvars gerado"
    log_warn "db_password aleatoria salva em terraform.tfvars (no .gitignore)"
    log_warn "Guarde uma copia se for compartilhar com o grupo!"
else
    log_ok "terraform.tfvars presente"
fi

echo ""

###############################################################################
# Step 1: Bootstrap backend
###############################################################################
log_info "[1/5] Garantindo backend remoto (S3 + DynamoDB lock)..."
"$SCRIPT_DIR/bootstrap-backend.sh" > /tmp/bootstrap.log 2>&1 \
    && log_ok "Backend OK" \
    || { log_error "Bootstrap falhou. Veja /tmp/bootstrap.log"; cat /tmp/bootstrap.log; exit 1; }

echo ""

###############################################################################
# Step 2: Terraform init + plan
###############################################################################
log_info "[2/5] Terraform init + plan..."
cd "$ENV_DIR"

# Backend config dinamico (bucket sufixado com ACCOUNT_ID — unicidade global)
BUCKET="tc5-solidarytech-tfstate-${ACCOUNT_ID}"
TABLE="tc5-solidarytech-tflock-${ACCOUNT_ID}"

terraform init -input=false -reconfigure \
    -backend-config="bucket=${BUCKET}" \
    -backend-config="dynamodb_table=${TABLE}" \
    > /tmp/tf-init.log 2>&1 \
    && log_ok "Init OK (backend: s3://${BUCKET})" \
    || { log_error "terraform init falhou. Veja /tmp/tf-init.log"; cat /tmp/tf-init.log; exit 1; }

terraform plan -out=tfplan.binary -input=false 2>&1 | tail -20
echo ""

###############################################################################
# Step 3: Apply (com confirmacao manual se nao auto-approve)
###############################################################################
log_info "[3/5] Terraform apply..."

if [ -z "$AUTO_APPROVE" ]; then
    echo ""
    log_warn "Revise o plano acima. Pronto para aplicar?"
    read -rp "Digite 'apply' para continuar (qualquer outra coisa cancela): " CONFIRM
    if [ "$CONFIRM" != "apply" ]; then
        log_warn "Apply cancelado pelo usuario."
        rm -f tfplan.binary
        exit 0
    fi
fi

log_info "Aplicando (pode levar ~15-20 minutos)..."
terraform apply -input=false tfplan.binary
rm -f tfplan.binary
log_ok "Apply concluido"

echo ""

###############################################################################
# Step 4: Configurar kubectl
###############################################################################
log_info "[4/5] Configurando kubectl..."

CLUSTER_NAME=$(terraform output -raw cluster_name)
REGION=$(terraform output -raw region)

aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" > /dev/null
log_ok "kubeconfig atualizado para cluster: $CLUSTER_NAME"

log_info "Validando acesso ao cluster..."
kubectl get nodes
echo ""

###############################################################################
# Step 5: Build inicial + push imagens pro ECR
###############################################################################
log_info "[5/10] Build/push imagens iniciais pro ECR..."

ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com"
aws ecr get-login-password --region "$REGION" | \
    docker login --username AWS --password-stdin "$ECR_REGISTRY" > /dev/null

# Verifica se imagens ja existem (CI Sprint 3 ja deve ter pushado)
SKIP_BUILD=true
for svc in ngo-service donation-service volunteer-service; do
    IMAGE_COUNT=$(aws ecr list-images --repository-name "$svc" --region "$REGION" \
        --query 'length(imageIds)' --output text 2>/dev/null || echo "0")
    if [ "$IMAGE_COUNT" = "0" ] || [ "$IMAGE_COUNT" = "None" ]; then
        SKIP_BUILD=false
        break
    fi
done

if [ "$SKIP_BUILD" = "true" ]; then
    log_ok "Imagens ja existem no ECR (CI Sprint 3 pushou). Pulando build."
else
    log_info "Construindo e enviando 3 imagens (~5-8 min)..."
    for svc in ngo-service donation-service volunteer-service; do
        echo "  >>> Building $svc..."
        docker build --platform linux/amd64 \
            -t "$ECR_REGISTRY/$svc:latest" \
            "$PROJECT_DIR/microservices/$svc" > /tmp/docker-build-$svc.log 2>&1 \
            && docker push "$ECR_REGISTRY/$svc:latest" > /tmp/docker-push-$svc.log 2>&1 \
            && log_ok "$svc pushed" \
            || { log_error "Falha em $svc. Logs: /tmp/docker-{build,push}-$svc.log"; exit 1; }
    done
fi
echo ""

###############################################################################
# Step 6: Substituir placeholder <AWS_ACCOUNT_ID> nos manifestos GitOps
###############################################################################
log_info "[6/10] Atualizando placeholders nos manifestos..."

for svc in ngo-service donation-service volunteer-service; do
    DEPLOY_FILE="$PROJECT_DIR/gitops/$svc/deployment.yaml"
    if [ -f "$DEPLOY_FILE" ] && grep -q '<AWS_ACCOUNT_ID>' "$DEPLOY_FILE"; then
        sed -i.bak "s|<AWS_ACCOUNT_ID>|$ACCOUNT_ID|g" "$DEPLOY_FILE" && rm -f "$DEPLOY_FILE.bak"
        log_ok "$svc/deployment.yaml atualizado"
    fi
done

ARGOCD_FILE="$PROJECT_DIR/argocd/applications.yaml"
GITHUB_USER=$(git -C "$PROJECT_DIR" remote get-url origin 2>/dev/null \
    | sed -E 's|.*github\.com[:/]([^/]+)/.*|\1|')
if [ -f "$ARGOCD_FILE" ] && grep -q '<GITHUB_USER>' "$ARGOCD_FILE"; then
    sed -i.bak "s|<GITHUB_USER>|$GITHUB_USER|g" "$ARGOCD_FILE" && rm -f "$ARGOCD_FILE.bak"
    log_ok "argocd/applications.yaml atualizado (GITHUB_USER=$GITHUB_USER)"
fi

# Commitar mudancas pra que ArgoCD veja a versao final
if [ -n "$(git -C "$PROJECT_DIR" status --short gitops/ argocd/ 2>/dev/null)" ]; then
    log_info "Commitando placeholders preenchidos..."
    git -C "$PROJECT_DIR" add gitops/ argocd/
    git -C "$PROJECT_DIR" commit -m "chore: substitui placeholders ECR (account $ACCOUNT_ID) e GitHub user ($GITHUB_USER)" --quiet
    git -C "$PROJECT_DIR" push --quiet 2>/dev/null \
        && log_ok "Manifests commitados e enviados" \
        || log_warn "git push falhou — faca push manualmente antes do ArgoCD sync"
fi
echo ""

###############################################################################
# Step 7: Gerar + aplicar K8s Secrets
###############################################################################
log_info "[7/10] Gerando e aplicando K8s Secrets..."
"$SCRIPT_DIR/generate-secrets.sh"
"$SCRIPT_DIR/apply-secrets.sh"
echo ""

###############################################################################
# Step 8: Instalar ArgoCD
###############################################################################
log_info "[8/10] Instalando ArgoCD..."

if kubectl get namespace argocd > /dev/null 2>&1; then
    log_ok "ArgoCD namespace ja existe, pulando install"
else
    kubectl create namespace argocd
    kubectl apply -n argocd \
        -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml \
        --server-side > /dev/null
    log_info "Aguardando ArgoCD server ficar Available (ate 300s)..."
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
    # Expor via LoadBalancer (mais simples que port-forward)
    kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
    log_ok "ArgoCD instalado"
fi
echo ""

###############################################################################
# Step 9: Instalar NGINX Ingress Controller
###############################################################################
log_info "[9/10] Instalando NGINX Ingress Controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.0/deploy/static/provider/aws/deploy.yaml > /dev/null 2>&1 || true
log_ok "NGINX Ingress instalado"
echo ""

###############################################################################
# Step 10: Aplicar ArgoCD Applications + aguardar sync
###############################################################################
log_info "[10/10] Aplicando ArgoCD Applications..."
kubectl apply -f "$PROJECT_DIR/argocd/applications.yaml"
log_ok "Applications criadas"

log_info "Aguardando pods do solidarytech ficarem prontos (ate 5min)..."
for svc in ngo-service donation-service volunteer-service; do
    echo -n "  $svc... "
    kubectl rollout status deployment/$svc -n solidarytech --timeout=180s 2>/dev/null \
        && echo "ok" || echo "(pode demorar mais — verifique com kubectl)"
done
echo ""

###############################################################################
# Resumo final
###############################################################################
echo "============================================"
log_ok "Setup completo (Sprints 2-4)"
echo "============================================"
echo ""

ARGOCD_URL=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pendente")
ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "N/A")
INGRESS_URL=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pendente")

echo "ArgoCD:"
echo "  URL:   https://$ARGOCD_URL"
echo "  User:  admin"
echo "  Pass:  $ARGOCD_PASS"
echo ""
echo "Ingress (publico):"
echo "  http://$INGRESS_URL/ngos"
echo "  http://$INGRESS_URL/donations"
echo "  http://$INGRESS_URL/volunteers"
echo ""
echo "Verificar pods:  kubectl get pods -n solidarytech"
echo "Destruir:        ./scripts/destroy-all.sh"
echo "Renovar AWS:     ./scripts/update-aws-credentials.sh  (a cada 4h)"
