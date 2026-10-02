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
    key          = "demo/bootstrap/terraform.tfstate"
    region       = "ap-northeast-2"
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  # 크레덴셜이 다른 계정이면 plan/apply 를 즉시 차단 (멀티계정 오적용 방지)
  allowed_account_ids = [var.account_id]
  default_tags {
    tags = var.default_tags
  }
}
