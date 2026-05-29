# SRE — SLI / SLO / SLA do donation-service

> Atende ao requisito do Tech Challenge FASE 5, item 1 (SRE):
> "Para o donation-service, defina e documente, no mínimo, dois SLIs
> (Service Level Indicators) baseados nas Golden Metrics. Estabeleça o
> SLO (Service Level Objective) para cada um. Crie um Dashboard SRE..."

## Service crítico em foco

**donation-service** — o **Hot Path** da plataforma SolidaryTech.
Processa cada doação recebida, persiste no PostgreSQL e publica evento
SQS para notificação assíncrona. Indisponibilidade ou degradação tem
impacto **direto na receita** das ONGs parceiras.

---

## 1. SLI #1 — Availability (Taxa de Sucesso)

### Definição

Razão de requisições HTTP do `donation-service` que **NÃO** retornam erro 5xx
sobre o total de requisições, em janela móvel de 5 minutos.

### Fórmula PromQL

```promql
sli:donation_service:availability:ratio_5m =
  sum(rate(http_server_request_total{service_name="donation-service", http_response_status_code!~"5.."}[5m]))
  /
  sum(rate(http_server_request_total{service_name="donation-service"}[5m]))
```

### Onde está implementado

- **Métrica fonte:** emitida pela instrumentação OTel automática (`otelhttp.NewHandler` no Go)
- **Coleta:** OTel Collector → Prometheus remote_write
- **Recording rule:** `gitops/monitoring/alerting/prometheus-rules.yaml` group `solidarytech.donation.slo`

---

## 2. SLI #2 — Latência P95

### Definição

Percentil 95 da latência (segundos) de resposta do `donation-service`,
em janela móvel de 5 minutos.

### Fórmula PromQL

```promql
sli:donation_service:latency_p95:5m =
  histogram_quantile(0.95,
    sum by (le) (rate(http_server_request_duration_seconds_bucket{service_name="donation-service"}[5m]))
  )
```

### Por quê P95 e não P50 ou P99

- **P50** (mediana): muito otimista — esconde caudas longas que afetam minoria
- **P95**: padrão da indústria — captura 95% das requisições, ainda razoável
- **P99**: muito sensível a outliers — pode disparar alerta por uma única request lenta

Para o caminho crítico de doação, **P95 < 300ms** é o equilíbrio entre experiência do usuário (perceptível < 300ms) e custo de operação.

---

## 3. SLOs (Service Level Objectives)

| SLO | Objetivo | Error Budget mensal | Justificativa |
|-----|----------|---------------------|----------------|
| **Availability** | **≥ 99.9%** | 43min 48s downtime/mês | Padrão de mercado para sistemas de pagamento/doação não-financeiros. Aceitável dado o tier free de infra |
| **Latência P95** | **< 300ms** | 5% das requisições podem exceder | Perceptível pelo usuário < 300ms; UX de doação não pode degradar |

### Por que 99.9% e não 99.99% ou 99.5%

| SLO | Downtime/mês | Custo de infra | Adequado para |
|-----|--------------|----------------|---------------|
| 99% | 7h 18min | Baixo | Sistemas internos não-críticos |
| 99.5% | 3h 39min | Baixo | Aplicações com janelas de manutenção |
| **99.9%** ✅ | **43min** | **Médio** | **Sistemas user-facing comuns — escolhido** |
| 99.99% | 4min | Alto | Sistemas financeiros, pagamentos |
| 99.999% | 26s | Muito alto | Telecom, healthcare crítico |

99.9% é o ponto de equilíbrio: alto o suficiente pra preservar confiança da rede de doadores, baixo o suficiente pra ser viável com infra free-tier AWS Academy.

---

## 4. SLAs (Service Level Agreements) com ONGs parceiras

| Métrica | SLA contratual | Compensação se descumprido |
|---------|----------------|---------------------------|
| Disponibilidade mensal | **≥ 99.5%** | Relatório mensal de causa raiz + ações corretivas |
| Latência P95 | **< 500ms** | Idem |

> **SLA é mais permissivo que SLO propositalmente.** SLO é nossa meta interna
> (apertada); SLA é o compromisso externo (com margem de segurança).
> Padrão da indústria.

---

## 5. Error Budget — cálculo e gestão

### Cálculo

Com SLO de **99.9%** num mês de 30 dias:

```
Tempo total:    30 × 24 × 60 = 43.200 minutos
Allowed errors:  43.200 × (1 - 0.999) = 43.2 minutos
                                       ≈ 43 minutos / mês
```

### Burn rate alerts (multi-window)

| Burn rate | Tempo p/ esgotar | Severidade | Ação |
|-----------|------------------|------------|------|
| **14.4×** (consome 2% em 1h) | 2.08h | 🔴 Page (PagerDuty) | Halt deploys, war-room |
| **6×** (consome 5% em 6h) | 5h | 🟡 Discord warn | SRE on-call avalia |
| **1×** (consome 100% em 30d) | 30d | 🟢 Normal | Continuar normal |

**Regra atual implementada** (`gitops/monitoring/alerting/prometheus-rules.yaml`):

```yaml
- alert: DonationSLOFastBurn
  expr: |
    (1 - sli:donation_service:availability:ratio_5m) > (14.4 * (1 - 0.999))
  for: 2m
  labels:
    severity: critical
    slo: availability
```

### Decisão de deploy baseada em Error Budget

| Budget remanescente | Política |
|---------------------|----------|
| > 50% | Deploy normal |
| 25%-50% | Deploy apenas em horário comercial |
| < 25% | **Freeze de deploys** — apenas fixes críticos |
| 0% (esgotado) | Postmortem obrigatório + freeze automático |

---

## 6. Dashboard SRE no Grafana

Disponível em `Dashboards → SolidaryTech → SolidaryTech Overview`:

- **Painel "Error Rate (5xx) by Service"** — visualiza SLI #1
- **Painel "HTTP P95/P99 Latency"** — visualiza SLI #2
- **Linhas de threshold no SLO** (vermelho em > 5%, amarelo em > 1%)
- **Logs ao vivo do donation-service** (via Loki)
- **Pod restart count** (proxy de instabilidade)

Acesso: URL do LoadBalancer `prometheus-grafana`, credenciais via:
```bash
kubectl get secret grafana-admin -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d
```

---

## 7. MTTR (Mean Time To Recovery) — redução comprovada

Requisito do PDF: **"evidencie como a stack de observabilidade e as automações
de resposta a incidentes ajudam a reduzir ativamente o MTTR"**.

### Stack de redução de MTTR

| Camada | Tempo de redução | Como |
|--------|------------------|------|
| **Detecção (MTTD)** | < 2min | Prometheus + Alertmanager + AIOps New Relic |
| **Notificação** | < 30s | Discord + PagerDuty paralelos |
| **Triagem** | < 5min | Runbooks em `docs/ITSM-LIFECYCLE.md` + dashboards prontos |
| **Mitigação automática** | < 1min | Self-healing workflow GitHub Actions (`gh workflow run`) |
| **Validação** | < 2min | Health checks automáticos via Ingress |
| **Comunicação** | Auto | Templates de status em ITSM-LIFECYCLE.md |
| **Total target MTTR** | **< 15min** | Hot Path SLO |

### Evidência empírica

Self-healing workflow disparado no Sprint 5.5 — restart completo do `donation-service`:
- **Tempo total:** 43 segundos
- **Pods reiniciados:** 3/3
- **Discord notificações:** "INICIADO" + "CONCLUIDO"
- **Run ID:** [#26662680566](https://github.com/rivachef/TC5-SolidaryTech/actions/runs/26662680566)

> **Sem self-healing**, o mesmo procedimento manual (SRE recebe page → loga no console → roda `kubectl rollout restart` → valida) levaria ~5-10min.
> **Redução de MTTR: 80%+** no cenário "pod crashloop em horário comercial".

---

## 8. Resumo executivo (1 página)

| | |
|---|---|
| **Serviço crítico** | donation-service (Hot Path) |
| **SLI 1** | Availability 5m (% sem 5xx) |
| **SLI 2** | Latência P95 5m |
| **SLO Availability** | ≥ 99.9% (43min downtime/mês) |
| **SLO Latência P95** | < 300ms |
| **SLA contratual ONGs** | ≥ 99.5% disponibilidade, P95 < 500ms |
| **Error Budget alert** | Fast burn 14.4× → PagerDuty + Discord + war-room |
| **MTTR target** | < 15min |
| **MTTR evidência empírica** | 43s via self-healing automático |
| **Dashboard** | Grafana `SolidaryTech Overview` |
| **Runbooks** | `docs/ITSM-LIFECYCLE.md` |
