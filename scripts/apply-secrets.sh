#!/bin/bash
###############################################################################
# apply-secrets.sh
#
# Aplica os secrets gerados por generate-secrets.sh no cluster.
# Cria o namespace solidarytech se nao existir.
#
# Uso:
#   ./scripts/generate-secrets.sh
#   ./scripts/apply-secrets.sh
###############################################################################
set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$SCRIPT_DIR/_generated"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $1"; }

if [ ! -d "$OUT_DIR" ] || [ -z "$(ls -A "$OUT_DIR"/*.yaml 2>/dev/null)" ]; then
    log_err "Sem secrets em $OUT_DIR. Rode primeiro: ./scripts/generate-secrets.sh"
    exit 1
fi

log_info "Garantindo namespace solidarytech..."
kubectl get namespace solidarytech > /dev/null 2>&1 || kubectl create namespace solidarytech

log_info "Aplicando secrets..."
for f in "$OUT_DIR"/*.yaml; do
    kubectl apply -f "$f"
done

log_ok "Secrets aplicados:"
kubectl get secrets -n solidarytech --no-headers
