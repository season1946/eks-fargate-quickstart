terraform {
  required_version = ">= 1.0.1"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.66.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.6.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.4.1"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.13.1"
    }
  }
}

provider "aws" {
  region = var.region
}

provider "kubernetes" {
  experiments {
    manifest_resource = true
  }
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    token                  = data.aws_eks_cluster_auth.cluster.token
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  }
}

provider "kubectl" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  load_config_file       = false
  apply_retry_count      = 5
}

data "aws_eks_cluster" "cluster" {
  name = module.aws-eks-accelerator-for-terraform.eks_cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.aws-eks-accelerator-for-terraform.eks_cluster_id
}

#---------------------------------------------------------------
# Terraform VPC remote state import from S3
#---------------------------------------------------------------
data "terraform_remote_state" "vpc_s3_backend" {
  backend = "s3"
  config = {
    bucket = var.tf_state_vpc_s3_bucket
    key    = var.tf_state_vpc_s3_key
    region = var.region
  }
}

locals {
  tenant      = var.tenant
  environment = var.environment
  zone        = var.zone

  kubernetes_version = var.kubernetes_version
  terraform_version  = "Terraform v1.0.1"

  vpc_id             = data.terraform_remote_state.vpc_s3_backend.outputs.vpc_id
  private_subnet_ids = data.terraform_remote_state.vpc_s3_backend.outputs.private_subnets
  public_subnet_ids  = data.terraform_remote_state.vpc_s3_backend.outputs.public_subnets
}

module "aws-eks-accelerator-for-terraform" {
  source = "../../.."

  tenant            = local.tenant
  environment       = local.environment
  zone              = local.zone
  terraform_version = local.terraform_version

  # EKS Cluster VPC and Subnets
  vpc_id             = local.vpc_id
  private_subnet_ids = local.private_subnet_ids

  # EKS CONTROL PLANE VARIABLES
  kubernetes_version = local.kubernetes_version

  # EKS MANAGED NODE GROUPS
  managed_node_groups = {
    mg_4 = {
      node_group_name = "managed-ondemand"
      instance_types  = ["m5.xlarge"]
      subnet_ids      = local.private_subnet_ids
    }
  }
}

module "kubernetes-addons" {
  source = "../../../modules/kubernetes-addons"

  eks_cluster_id               = module.aws-eks-accelerator-for-terraform.eks_cluster_id
  eks_worker_security_group_id = module.aws-eks-accelerator-for-terraform.worker_security_group_id

  # EKS Managed Add-ons
  enable_amazon_eks_vpc_cni            = true
  enable_amazon_eks_coredns            = true
  enable_amazon_eks_kube_proxy         = true
  enable_amazon_eks_aws_ebs_csi_driver = true

  #K8s Add-ons
  enable_aws_load_balancer_controller = true
  enable_metrics_server               = true
  enable_cluster_autoscaler           = true
  enable_vpa                          = true
  enable_prometheus                   = true
  enable_ingress_nginx                = true
  enable_aws_for_fluentbit            = true
  enable_argocd                       = true
  enable_fargate_fluentbit            = false
  enable_argo_rollouts                = true
  enable_kubernetes_dashboard         = true
  enable_yunikorn                     = true

  depends_on = [module.aws-eks-accelerator-for-terraform.managed_node_groups]
}
