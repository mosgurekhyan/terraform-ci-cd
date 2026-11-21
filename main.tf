# # variable "aws_access_key" {
# #   type      = string
# #   sensitive = true
# # }
# # variable "aws_secret_key" {
# #   type      = string
# #   sensitive = true
# # }
# variable "aws_region" {
#   type    = string
#   default = "eu-central-1"
# }

# variable "app_version" {
#   type        = string
#   description = "Bump this (or pass git SHA) to roll out a new instance"
#   default     = "v1"
# }

# provider "aws" {
#   region     = var.aws_region
# }

# resource "aws_security_group" "server_security_group" {
#   name        = "my-sg22"
#   description = "Allow ssh and http"

#   ingress {
#     from_port   = 22
#     to_port     = 22
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   ingress {
#     from_port   = 80
#     to_port     = 80
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
# }

# resource "aws_instance" "myserver" {
#   ami                    = "ami-086aab8b3eb42a4f0"
#   instance_type          = "t3.micro"
#   vpc_security_group_ids = [aws_security_group.server_security_group.id]

#   user_data = <<-EOF
#     #!/bin/bash
#     set -euxo pipefail
#     apt-get update -y
#     apt-get install -y nginx
#     systemctl enable --now nginx
#     echo "<h1>Hello from Terraform nginx</h1>" > /var/www/html/index.html
#   EOF

#   lifecycle {
#     create_before_destroy = true
#   }

#   tags = {
#     Name    = "terraform-nginx"
#     Version = var.app_version
#   }
# }

# resource "aws_eip" "server_ip" {
#   instance = aws_instance.myserver.id
#   domain   = "vpc"
# }

terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_vpc" "default" { default = true }
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# --- SG (stable, unique name, safe replace) ---
resource "aws_security_group" "server_security_group" {
  name_prefix = "my-sg-"
  description = "Allow ssh and http"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle { create_before_destroy = true }
}

# --- Instance (zero-downtime replace) ---
resource "aws_instance" "myserver" {
  ami                    = var.ami_id
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.server_security_group.id]

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail
    apt-get update -y
    apt-get install -y nginx
    systemctl enable --now nginx
    echo "<h1>Version ${var.app_version}</h1>" > /var/www/html/index.html
  EOF

  lifecycle { create_before_destroy = true }

  tags = {
    Name    = "terraform-nginx"
    Version = var.app_version
  }
}

# --- ALB (switches traffic after health check) ---
resource "aws_security_group" "lb" {
  name_prefix = "lb-sg-"
  description = "ALB http"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  lifecycle { create_before_destroy = true }
}

resource "aws_lb" "web" {
  name               = "nginx-lb"
  load_balancer_type = "application"
  subnets            = data.aws_subnets.default.ids
  security_groups    = [aws_security_group.lb.id]
}

resource "aws_lb_target_group" "web" {
  name     = "nginx-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id
  health_check { path = "/" }
}

resource "aws_lb_target_group_attachment" "web" {
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.myserver.id
  port             = 80
}

resource "aws_lb_listener" "web" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}