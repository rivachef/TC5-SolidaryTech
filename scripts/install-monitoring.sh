#!/bin/bash
###############################################################################
# install-monitoring.sh
#
# Instala stack de observabilidade no cluster EKS:
#   Prometheus (kube-prometheus-stack) + Grafana + Alertmanager
#   Loki + Promtail (logs)
#   OpenTelemetry Collector (hub: traces+metrics->NR, logs->Loki, metrics->Prom)
#
# Pre-requisitos:
#   - kubectl conectado ao cluster
#   - helm 3.12+ instalado
#   - (opcional) gitops/monitoring/newrelic-secret.yaml aplicado para APM
###############################################################################
set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MONITORING_DIR="$PROJECT_DIR/gitops/monitoring"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo "============================================"
echo "  SolidaryTech - Monitoring Stack Installer"
echo "============================================"
echo ""

# -------------------------------------------------------
# 1. Namespace
# -------------------------------------------------------
log_info "[1/6] Garantindo namespace monitoring..."
kubectl apply -f "$MONITORING_DIR/namespace.yaml"

# -------------------------------------------------------
# 2. Helm repos
# -------------------------------------------------------
log_info "[2/6] Adicionando Helm repos..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts > /dev/null
helm repo add grafana https://grafana.github.io/helm-charts > /dev/null
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts > /dev/null
helm repo update > /dev/null
log_ok "Repos atualizados"

# -------------------------------------------------------
# 3. kube-prometheus-stack
# -------------------------------------------------------
log_info "[3/6] Instalando kube-prometheus-stack (Prometheus + Grafana + Alertmanager)..."
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --values "$MONITORING_DIR/prometheus/values.yaml" \
    --wait --timeout 10m

# -------------------------------------------------------
# 4. Loki
# -------------------------------------------------------
log_info "[4/6] Instalando Loki..."
helm upgrade --install loki grafana/loki \
    --namespace monitoring \
    --values "$MONITORING_DIR/loki/values.yaml" \
    --wait --timeout 10m

# -------------------------------------------------------
# 5. Promtail
# -------------------------------------------------------
log_info "[5/6] Instalando Promtail..."
helm upgrade --install promtail grafana/promtail \
    --namespace monitoring \
    --values "$MONITORING_DIR/promtail/values.yaml" \
    --wait --timeout 5m

# -------------------------------------------------------
# 6. OTel Collector
# -------------------------------------------------------
log_info "[6/6] Instalando OpenTelemetry Collector..."
helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
    --namespace monitoring \
    --values "$MONITORING_DIR/otel-collector/values.yaml" \
    --wait --timeout 5m

echo ""
log_ok "Stack instalada"

# -------------------------------------------------------
# Aplicar PrometheusRules customizadas (SLO + Hot Path)
# -------------------------------------------------------
if [ -f "$MONITORING_DIR/alerting/prometheus-rules.yaml" ]; then
    log_info "Aplicando PrometheusRules customizadas..."
    kubectl apply -f "$MONITORING_DIR/alerting/prometheus-rules.yaml"
    log_ok "Alertas SLO+pods+resources aplicados"
fi

# -------------------------------------------------------
# Dashboard customizado (com substituicao do Loki datasource UID)
# -------------------------------------------------------
DASHBOARD_FILE="$MONITORING_DIR/grafana/dashboards/solidarytech-overview.json"
if [ -f "$DASHBOARD_FILE" ]; then
    log_info "Carregando dashboard Grafana customizado..."
    kubectl rollout status deployment/prometheus-grafana -n monitoring --timeout=120s > /dev/null 2>&1

    GRAFANA_POD=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}')
    LOKI_UID=""
    for i in $(seq 1 12); do
        LOKI_UID=$(kubectl exec -n monitoring "$GRAFANA_POD" -c grafana -- \
            curl -sf http://localhost:3000/api/datasources -u admin:solidarytech2026 2>/dev/null | \
            python3 -c "import sys,json; ds=json.load(sys.stdin); print(next((d['uid'] for d in ds if d['type']=='loki'),''))" 2>/dev/null)
        [ -n "$LOKI_UID" ] && break
        sleep 5
    done

    if [ -z "$LOKI_UID" ]; then
        log_warn "Loki datasource UID nao encontrado — paineis de log podem nao funcionar"
        LOKI_UID="loki"
    fi

    DASHBOARD_TMP=$(mktemp)
    sed "s|<LOKI_DS_UID>|$LOKI_UID|g" "$DASHBOARD_FILE" > "$DASHBOARD_TMP"

    kubectl create configmap solidarytech-dashboard \
        --from-file=solidarytech-overview.json="$DASHBOARD_TMP" \
        --namespace monitoring \
        --dry-run=client -o yaml | \
        kubectl label --local -f - grafana_dashboard=1 -o yaml | \
        kubectl annotate --local -f - grafana_folder=SolidaryTech -o yaml | \
        kubectl apply -f -

    rm -f "$DASHBOARD_TMP"
    log_ok "Dashboard aplicado"
fi

echo ""
echo "============================================"
echo "  Acessos"
echo "============================================"
GRAFANA_URL=$(kubectl get svc prometheus-grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pendente")
echo ""
echo "Grafana:"
echo "  URL:  http://$GRAFANA_URL"
echo "  User: admin"
echo "  Pass: solidarytech2026"
echo ""
echo "OTel Collector (endpoint para os microsservicos):"
echo "  gRPC: otel-collector-opentelemetry-collector.monitoring.svc.cluster.local:4317"
echo "  HTTP: otel-collector-opentelemetry-collector.monitoring.svc.cluster.local:4318"
echo ""
if ! kubectl get secret newrelic-license-key -n monitoring > /dev/null 2>&1; then
    log_warn "Secret newrelic-license-key NAO aplicado — distributed tracing nao ira pro New Relic"
    echo "  Aplicar com:"
    echo "    cp gitops/monitoring/newrelic-secret.yaml.example gitops/monitoring/newrelic-secret.yaml"
    echo "    # editar a license-key"
    echo "    kubectl apply -f gitops/monitoring/newrelic-secret.yaml"
    echo "    kubectl rollout restart deployment/otel-collector-opentelemetry-collector -n monitoring"
fi
