# Development Environment Configuration
# Demonstrates how to compose modules for a complete environment

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # Uncomment for remote state in production
  # backend "s3" {
  #   bucket         = "ddgo-terraform-state"
  #   key            = "dev/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "ddgo-terraform-locks"
  #   encrypt        = true
  # }
}

# -----------------------------------------------------------------------------
# Provider Configuration
# -----------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "ddgo"
    }
  }
}

# -----------------------------------------------------------------------------
# Local Variables
# -----------------------------------------------------------------------------

locals {
  environment  = "dev"
  project_name = var.project_name

  common_tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "terraform"
  }
}

# -----------------------------------------------------------------------------
# VPC Module
# -----------------------------------------------------------------------------

module "vpc" {
  source = "../../modules/vpc"

  project_name = local.project_name
  environment  = local.environment
  aws_region   = var.aws_region

  vpc_cidr   = var.vpc_cidr
  az_count   = 2

  # Cost optimization for dev
  enable_nat_gateway = true
  single_nat_gateway = true  # Use single NAT for dev to save costs

  enable_flow_logs     = true
  enable_vpc_endpoints = true

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# ALB Module
# -----------------------------------------------------------------------------

module "alb" {
  source = "../../modules/alb"

  project_name      = local.project_name
  environment       = local.environment
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids

  container_port    = 5000
  health_check_path = "/health"

  # HTTP only for dev (no SSL)
  ssl_certificate_arn = ""

  enable_deletion_protection = false

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# RDS Module
# -----------------------------------------------------------------------------

module "rds" {
  source = "../../modules/rds"

  project_name        = local.project_name
  environment         = local.environment
  vpc_id              = module.vpc.vpc_id
  database_subnet_ids = module.vpc.database_subnet_ids

  allowed_security_group_ids = [module.ecs.security_group_id]

  # Small instance for dev
  instance_class        = "db.t3.micro"
  allocated_storage     = 20
  max_allocated_storage = 50

  # Dev settings
  multi_az                = false
  deletion_protection     = false
  skip_final_snapshot     = true
  backup_retention_period = 7

  # Monitoring
  monitoring_interval          = 60
  performance_insights_enabled = true
  create_cloudwatch_alarms     = true

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# ECS Module
# -----------------------------------------------------------------------------

module "ecs" {
  source = "../../modules/ecs"

  project_name       = local.project_name
  environment        = local.environment
  aws_region         = var.aws_region
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  alb_security_group_ids = [module.alb.security_group_id]
  target_group_arn       = module.alb.target_group_arn

  # Container configuration
  container_image = var.container_image
  container_port  = 5000
  task_cpu        = 256
  task_memory     = 512

  # Scaling configuration for dev
  desired_count = 1
  min_capacity  = 1
  max_capacity  = 3

  # Database configuration
  db_host = module.rds.db_instance_address
  db_port = module.rds.db_instance_port
  db_name = "ddgo"

  # Secrets
  secrets = [
    {
      name      = "DB_USER"
      valueFrom = "${module.rds.secrets_manager_secret_arn}:username::"
    },
    {
      name      = "DB_PASSWORD"
      valueFrom = "${module.rds.secrets_manager_secret_arn}:password::"
    }
  ]

  secrets_arns = [module.rds.secrets_manager_secret_arn]

  # Features
  enable_container_insights = true
  use_fargate_spot          = true  # Cost savings for dev

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "alb_dns_name" {
  description = "ALB DNS name - use this to access the application"
  value       = module.alb.alb_dns_name
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs.cluster_name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = module.ecs.service_name
}

output "rds_endpoint" {
  description = "RDS endpoint"
  value       = module.rds.db_instance_endpoint
}

output "rds_secret_arn" {
  description = "ARN of the secret containing database credentials"
  value       = module.rds.secrets_manager_secret_arn
}

output "application_url" {
  description = "Application URL"
  value       = "http://${module.alb.alb_dns_name}"
}
