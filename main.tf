# terraform {
#   required_providers {
#     aws = { source = "hashicorp/aws", version = "~> 5.0" }
#   }
# }

# provider "aws" {
#   region = var.aws_region
# }

# locals {
#   ingress_ports = [22, 80]
# }

# data "aws_vpc" "default" { default = true }
# data "aws_subnets" "default" {
#   filter {
#     name   = "vpc-id"
#     values = [data.aws_vpc.default.id]
#   }
# }

# resource "aws_key_pair" "deployer" {
#   key_name   = "terraform-ansible-key"
#   public_key = file("${path.module}/ansible_key.pem.pub")
# }

# # --- SG (stable, unique name, safe replace) ---
# resource "aws_security_group" "server_security_group" {
#   name_prefix = "my-sg-"
#   description = "Allow ssh and http"
#   vpc_id      = data.aws_vpc.default.id

#   dynamic "ingress" {
#     for_each = local.ingress_ports
#     content {
#       from_port   = ingress.value
#       to_port     = ingress.value
#       protocol    = "tcp"
#       cidr_blocks = ["0.0.0.0/0"]
#     }
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   lifecycle { create_before_destroy = true }
# }

# # --- Instance (zero-downtime replace) ---
# resource "aws_instance" "myserver" {
#   ami                    = var.ami_id
#   instance_type          = "t3.micro"
#   vpc_security_group_ids = [aws_security_group.server_security_group.id]

#   user_data = <<-EOF
#     #!/bin/bash
#     set -euxo pipefail
#     apt-get update -y
#     apt-get install -y nginx
#     systemctl enable --now nginx
#     echo "<h1>Version ${var.app_version}</h1>" > /var/www/html/index.html
#   EOF

#   lifecycle { create_before_destroy = true }

#   tags = {
#     Name    = "terraform-nginx"
#     Version = var.app_version
#   }
# }

# # --- ALB (switches traffic after health check) ---
# resource "aws_security_group" "lb" {
#   name_prefix = "lb-sg-"
#   description = "ALB http"
#   vpc_id      = data.aws_vpc.default.id

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
#   lifecycle { create_before_destroy = true }
# }

# resource "aws_lb" "web" {
#   name               = "nginx-lb"
#   load_balancer_type = "application"
#   subnets            = data.aws_subnets.default.ids
#   security_groups    = [aws_security_group.lb.id]
# }

# resource "aws_lb_target_group" "web" {
#   name     = "nginx-tg"
#   port     = 80
#   protocol = "HTTP"
#   vpc_id   = data.aws_vpc.default.id
#   health_check { path = "/" }
# }

# resource "aws_lb_target_group_attachment" "web" {
#   target_group_arn = aws_lb_target_group.web.arn
#   target_id        = aws_instance.myserver.id
#   port             = 80
# }

# resource "aws_lb_listener" "web" {
#   load_balancer_arn = aws_lb.web.arn
#   port              = 80
#   protocol          = "HTTP"
#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.web.arn
#   }
# }

terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  ingress_ports = [22, 80]
}

data "aws_vpc" "default" { default = true }
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Add this variable at the top of your main.tf (or variables.tf)
variable "ssh_public_key" {
  type        = string
  description = "SSH public key for EC2 instances"
}

resource "aws_key_pair" "deployer" {
  key_name_prefix = "terraform-key-"
  public_key = var.ssh_public_key
}


# --- SG (stable, unique name, safe replace) ---
resource "aws_security_group" "server_security_group" {
  name_prefix = "my-sg-"
  description = "Allow ssh and http"
  vpc_id      = data.aws_vpc.default.id

  dynamic "ingress" {
    for_each = local.ingress_ports
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
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

  # ADDED: Attach the SSH Key back to the instance
  key_name = aws_key_pair.deployer.key_name

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
  name_prefix        = "nginx-"
  load_balancer_type = "application"
  subnets            = data.aws_subnets.default.ids
  security_groups    = [aws_security_group.lb.id]

  lifecycle { create_before_destroy = true }
}

resource "aws_lb_target_group" "web" {
  name_prefix = "nginx-"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  # ADDED: Explicitly define target type and health check protocol
  target_type = "instance"

  health_check {
    path     = "/"
    protocol = "HTTP"
    matcher  = "200"
  }
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

# ADDED: Output the ALB DNS name so you can easily access it
output "alb_dns_name" {
  value = aws_lb.web.dns_name
}