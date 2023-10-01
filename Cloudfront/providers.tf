terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.13.1"
    }
  }
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "default-mf"
    workspaces {
      name = "Cloudfront"
    }
  }
}


/*
Switch backend to terraform cloud

backend "remote" {
    hostname     = "app.terraform.io"
    organization = "default-mf"
    workspaces {
      name = "workspace1"
    }
  }
  

Swtich to s3 backend

backend "s3" {
    bucket = "terraform-state-file-mf37" // tf state will be stored here
    key    = "web_host/resume/s3_cdn/infra"
    region = "us-east-1"
  }

Switch to local

backend "local" {
    path = "terraform.tfstate"
  }

*/