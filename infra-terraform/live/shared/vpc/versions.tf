terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket       = "demo-terraform-tfstate"
    key          = "demo/shared/vpc/terraform.tfstate"
    region       = "ap-northeast-2"
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  allowed_account_ids = [var.account_id]

  default_tags {
    tags = var.default_tags
  }
}
