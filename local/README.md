# SolidaryTech — Ambiente Local (Docker Compose)

Este diretorio contem tudo que e necessario para subir os 3 microsservicos da SolidaryTech em ambiente local, sem depender de credenciais AWS reais.

## Stack local

| Container | Imagem | Funcao | Porta exposta |
|-----------|--------|--------|---------------|
| `solidary-postgres` | postgres:16-alpine | 2 bancos: `ngo_db` e `donation_db` | 5432 |
| `solidary-localstack` | localstack/localstack:3 | Simula AWS (SQS + DynamoDB) | 4566 |
| `solidary-ngo` | build local | ngo-service (Python/Flask) | 8081 |
| `solidary-donation` | build local | donation-service (Go) — Hot Path | 8082 |
| `solidary-volunteer` | build local | volunteer-service (Python/Flask) | 8083 |

## Pre-requisitos

- Docker 24+ com Docker Compose v2
- Portas livres no host: `5432`, `4566`, `8081`, `8082`, `8083`

## Subir o ambiente

```bash
cd local/
docker compose up --build -d
```

Acompanhar logs ate todos os servicos ficarem prontos:

```bash
docker compose logs -f
```

Verificar status:

```bash
docker compose ps
```

## Validar (smoke tests)

```bash
# Health checks dos 3 servicos
curl http://localhost:8081/health
curl http://localhost:8082/health
curl http://localhost:8083/health

# ngo-service: listar ONGs (vem com 2 seedadas)
curl http://localhost:8081/ngos

# ngo-service: criar nova ONG
curl -X POST http://localhost:8081/ngos \
  -H "Content-Type: application/json" \
  -d '{"name":"Casa do Doador","email":"contato@casadoador.org","cause":"Fome","city":"São Paulo"}'

# donation-service: criar doacao (ngo_id 1 = Anjos de Patas)
curl -X POST http://localhost:8082/donations \
  -H "Content-Type: application/json" \
  -d '{"ngo_id":1,"amount":50.00,"donor_name":"Luiz Costa"}'

# donation-service: listar doacoes
curl http://localhost:8082/donations

# volunteer-service: cadastrar voluntario
curl -X POST http://localhost:8083/volunteers \
  -H "Content-Type: application/json" \
  -d '{"name":"Maria Silva","email":"maria@example.com","ngo_id":1}'

# volunteer-service: listar voluntarios de uma ONG
curl http://localhost:8083/volunteers/1

# LocalStack: verificar mensagens na fila SQS
docker exec solidary-localstack \
  awslocal sqs receive-message \
  --queue-url http://localhost:4566/000000000000/solidary-donations
```

## Parar

```bash
# Mantem dados (volume postgres-data)
docker compose down

# Apaga tudo, incluindo dados do Postgres
docker compose down -v
```

## Como funciona

### Postgres com 2 databases
O script `postgres/init.sh` roda no primeiro boot e executa:
1. `CREATE DATABASE ngo_db; CREATE DATABASE donation_db;`
2. Aplica o schema de cada servico (montado como volume read-only a partir de `microservices/*/db/init.sql`)

### LocalStack como AWS local
- Servicos habilitados: `sqs` + `dynamodb`
- Script `localstack/init.sh` (montado em `/etc/localstack/init/ready.d/`) cria automaticamente a fila `solidary-donations` e a tabela `SolidaryTechVolunteers` no primeiro boot.
- Os microsservicos apontam para `http://localstack:4566` via env `AWS_ENDPOINT_URL`.

### AWS_ENDPOINT_URL nos servicos
Os SDKs originalmente fornecidos (aws-sdk-go v1 e boto3 1.26) nao leem `AWS_ENDPOINT_URL` nativamente. Adicionamos suporte minimo via codigo:
- `donation-service/main.go`: 4 linhas extra na configuracao do SQS
- `volunteer-service/app.py`: parametro `endpoint_url=` no `boto3.resource`

Quando `AWS_ENDPOINT_URL` esta vazio (producao na AWS real), o comportamento e identico ao original.

## Troubleshooting

| Sintoma | Causa provavel | Solucao |
|---------|----------------|---------|
| `postgres` nao inicia, init.sh ja rodou antes | Volume `postgres-data` tem dados antigos | `docker compose down -v && docker compose up -d` |
| `donation-service` loga "AWS SQS desativada" | Falta `AWS_SQS_URL` ou `AWS_REGION` no env | Conferir `docker-compose.yml` |
| `localstack` health falha | Servico ainda inicializando | Esperar 30-60s, healthcheck cobre |
| Build falha em ARM (M1/M2/M3) | Imagem nao multi-arch | Usar `--platform linux/amd64` no build |

## Variaveis de ambiente

Copie `.env.example` para `.env` se quiser sobrescrever defaults:

```bash
cp .env.example .env
```

Variaveis disponiveis:
- `POSTGRES_USER` (default: `solidary`)
- `POSTGRES_PASSWORD` (default: `solidary_dev_pass`)

Em producao na AWS, todas as credenciais virao de Secrets Manager / SSM Parameter Store + IRSA, nao destas envs.
