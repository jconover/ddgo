# Development Environment Variables

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "ddgo"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "container_image" {
  description = "Container image to deploy"
  type        = string
  default     = "nginx:alpine"  # Placeholder - will be replaced by CI/CD
}
