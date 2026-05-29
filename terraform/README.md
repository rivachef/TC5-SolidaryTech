# Terraform — SolidaryTech (FASE 5)

Infraestrutura como Codigo para o Hackathon SolidaryTech. Reusa o padrao modular validado na FASE 3 do ToggleMaster, com evolucoes para:
- Suporte a multi-environment (primary + DR) via `environments/`
- Tags FinOps obrigatorias aplicadas globalmente
- ECR com lifecycle policy + scan on push
- SQS com Dead Letter Queue
- DynamoDB com PITR habilitado e preparado para Global Tables
- EKS com OIDC provider (pre-requisito para IRSA)

## Estrutura

```
terraform/
├── modules/                # blocos reutilizaveis (regiao-agnostico)
│   ├── networking/         # VPC + subnets + NAT + IGW + RTs + SGs
│   ├── eks/                # cluster + node group + OIDC provider
│   ├── databases/          # 2x RDS PostgreSQL + 1 DynamoDB
│   ├── messaging/          # SQS standard + DLQ
│   └── ecr/                # 3 repositorios com lifecycle policy
└── environments/
    ├── primary/            # us-east-1 (producao ativa)
    └── dr/                 # us-west-2 (Warm Standby - Sprint 6)
```

## Backend remoto

Cada environment tem state separado no mesmo bucket S3:
- `s3://tc5-solidarytech-terraform-state/environments/primary/terraform.tfstate`
- `s3://tc5-solidarytech-terraform-state/environments/dr/terraform.tfstate`

Lock via DynamoDB: `tc5-solidarytech-terraform-lock` (cross-region).

## Tags FinOps obrigatorias

Aplicadas via `default_tags` no provider AWS (propagam para todos os recursos suportados):

| Tag | Valor |
|-----|-------|
| `Project` | `SolidaryTech` |
| `Environment` | `Production` (primary) ou `DR` (dr) |
| `CostCenter` | `NGO-Core` |
| `ManagedBy` | `Terraform` |
| `Repository` | `rivachef/TC5-SolidaryTech` |

## Pre-requisitos (uma vez)

```bash
# Bucket de state
aws s3api create-bucket --bucket tc5-solidarytech-terraform-state --region us-east-1
aws s3api put-bucket-versioning --bucket tc5-solidarytech-terraform-state \
  --versioning-configuration Status=Enabled

# Tabela de lock
aws dynamodb create-table \
  --table-name tc5-solidarytech-terraform-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

## Subir ambiente primary

```bash
cd terraform/environments/primary
cp terraform.tfvars.example terraform.tfvars
# editar terraform.tfvars com lab_role_arn e db_password
terraform init
terraform plan
terraform apply
```

## AWS Academy

LabRole obrigatorio (nao posso criar IAM roles customizados). Sessao expira em 4h — renovar `AWS_SESSION_TOKEN` periodicamente.

ARN tipicamente: `arn:aws:iam::<ACCOUNT_ID>:role/LabRole`

Para descobrir:
```bash
aws sts get-caller-identity
```
