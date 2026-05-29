resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = var.cluster_role_arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = concat(var.private_subnet_ids, var.public_subnet_ids)
    endpoint_private_access = true
    endpoint_public_access  = var.endpoint_public_access
    security_group_ids      = [var.node_security_group_id]
  }

  # Logs do control plane (relevante para SRE/observabilidade da Fase 5)
  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  tags = {
    Name      = var.cluster_name
    Component = "kubernetes-cluster"
  }
}

# OIDC provider pre-requisito para IRSA (ArgoCD, Velero, External Secrets, etc.)
data "tls_certificate" "cluster" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer

  tags = {
    Name      = "${var.cluster_name}-oidc-provider"
    Component = "iam"
  }
}

resource "aws_launch_template" "nodes" {
  name_prefix            = "${var.cluster_name}-nodes-"
  vpc_security_group_ids = [var.node_security_group_id]

  metadata_options {
    http_tokens                 = "required" # IMDSv2 obrigatorio (security)
    http_put_response_hop_limit = 2          # 2 hops necessario para pods acessarem IMDS
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name      = "${var.cluster_name}-node"
      Component = "kubernetes-node"
    }
  }
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-ng"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.private_subnet_ids

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  instance_types = var.node_instance_types
  ami_type       = "AL2023_x86_64_STANDARD"
  disk_size      = var.node_disk_size

  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

  update_config {
    max_unavailable = 1
  }

  tags = {
    Name      = "${var.cluster_name}-ng"
    Component = "kubernetes-nodegroup"
  }

  depends_on = [aws_eks_cluster.this]
}
