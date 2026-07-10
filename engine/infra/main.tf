# infra/main.tf — AWS Infrastructure (Weekend 4)
#
# This deploys:
# - ECS Fargate cluster for containers
# - MSK (Managed Streaming for Kafka)
# - ECR repos for Docker images
# - VPC + networking
#
# Run:
#   cd infra
#   terraform init
#   terraform plan
#   terraform apply

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  default = "us-east-1"
}

variable "project_name" {
  default = "ocaml-trading"
}

# ── VPC ──────────────────────────────────────────────────────
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.5.1"

  name = "${var.project_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true  # Cost savings for a learning project
}

# ── ECR Repositories ─────────────────────────────────────────
resource "aws_ecr_repository" "engine" {
  name                 = "${var.project_name}/engine"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

resource "aws_ecr_repository" "sentiment" {
  name                 = "${var.project_name}/sentiment"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

# ── ECS Cluster ──────────────────────────────────────────────
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"
}

# ── MSK (Managed Kafka) ─────────────────────────────────────
# NOTE: MSK is expensive (~$200/month minimum). For a learning project,
# consider using a single EC2 instance with Kafka instead, or
# skip AWS Kafka and use Confluent Cloud's free tier.

# resource "aws_msk_cluster" "main" {
#   cluster_name           = "${var.project_name}-kafka"
#   kafka_version          = "3.6.0"
#   number_of_broker_nodes = 2
#
#   broker_node_group_info {
#     instance_type   = "kafka.t3.small"
#     client_subnets  = module.vpc.private_subnets
#     security_groups = [aws_security_group.kafka.id]
#     storage_info {
#       ebs_storage_info { volume_size = 10 }
#     }
#   }
# }

# ── Outputs ──────────────────────────────────────────────────
output "ecr_engine_url" {
  value = aws_ecr_repository.engine.repository_url
}

output "ecr_sentiment_url" {
  value = aws_ecr_repository.sentiment.repository_url
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}
