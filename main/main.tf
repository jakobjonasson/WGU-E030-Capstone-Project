provider "aws" {
  region = "us-east-2"
}

data "aws_availability_zones" "available" {}

locals {
    name = "BHM-VPC"
    azs  = slice(data.aws_availability_zones.available.names, 0, 2)
    tags = {"Project" = "BHM","Resource" = "VPC"}
}


module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"
  name   = local.name
  cidr   = "10.0.0.0/14"

  azs    = local.azs
  private_subnets = [for k, v in local.azs : "10.0.${k}.0/24"]
  database_subnets = [for k, v in local.azs : "10.1.${k}.0/24"]
  public_subnets = [for k, v in local.azs : "10.2.${k}.0/24"]

  private_subnet_names = [for k, v in local.azs : "ASGSubnet${k}"]
  database_subnet_names = [for k, v in local.azs : "RDSSubnet${k}"]
  public_subnet_names = [for k, v in local.azs : "PublicSubnet${k}"]

  create_database_subnet_group = true
  manage_default_network_acl = false
  manage_default_route_table = false
  manage_default_security_group = false

  enable_dns_hostnames = true
  enable_dns_support = true

  enable_nat_gateway = true

  #enable_vpn_gateway = true
  enable_dhcp_options = true
  dhcp_options_domain_name = "jjonasson.dev"
  dhcp_options_domain_name_servers = ["AmazonProvidedDNS", "8.8.4.4"]
}

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 5.0"
  vpc_id = module.vpc.vpc_id

  create_security_group = true
  security_group_name = "${local.name}-endpoints-sg"
  security_group_description = "Security group for VPC endpoints"
  security_group_rules = {
    ingress_https ={
        description = "Allow HTTPS traffic"
        cidr_blocks = [module.vpc.vpc_cidr_block]
    }
  }
  endpoints = {
    rds = {
      service = "rds"
      private_dns_enabled = true
      subnet_ids = module.vpc.database_subnets
      security_group_ids = [aws_security_group.rds.id]
    }
  }
}

# Resources

resource "aws_security_group" "rds" {
  name        = "${local.name}-rds-sg"
  description = "Security group for RDS instances"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Allow PostgreSQL traffic"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }

    tags = local.tags
}