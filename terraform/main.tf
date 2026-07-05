terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  default = "us-east-1"
}

variable "instance_type" {
  default = "t3.micro"
}

variable "public_key" {}

variable "project_name" {
  default = "fastapi-app"
}

# Key pair from the injected public key
resource "aws_key_pair" "app" {
  key_name   = "${var.project_name}-key"
  public_key = var.public_key
}

# VPC and networking - use default VPC
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security group for the EC2 instance
resource "aws_security_group" "app" {
  name        = "${var.project_name}-sg"
  description = "Security group for ${var.project_name} app server"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-sg"
    Project = var.project_name
  }
}

# Latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# EC2 instance
resource "aws_instance" "app" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.app.key_name
  vpc_security_group_ids = [aws_security_group.app.id]
  subnet_id              = tolist(data.aws_subnets.default.ids)[0]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name    = "${var.project_name}-app"
    Project = var.project_name
  }
}

# Static / Elastic IP so the address survives stop/start
resource "aws_eip" "app" {
  instance = aws_instance.app.id
  domain   = "vpc"

  tags = {
    Name    = "${var.project_name}-eip"
    Project = var.project_name
  }
}

output "instance_public_ip" {
  value       = aws_eip.app.public_ip
  description = "Static public IP of the app server"
}

output "app_url" {
  value       = "http://${aws_eip.app.public_ip}"
  description = "Public URL of the deployed application"
}