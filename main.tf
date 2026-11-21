# variable "aws_access_key" {
#   type      = string
#   sensitive = true
# }
# variable "aws_secret_key" {
#   type      = string
#   sensitive = true
# }
variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

provider "aws" {
  region     = var.aws_region
}

resource "aws_security_group" "server_security_group" {
  name        = "my-sg22"
  description = "Allow ssh and http"

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
}

resource "aws_instance" "myserver" {
  ami                    = "ami-086aab8b3eb42a4f0"
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.server_security_group.id]

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail
    apt-get update -y
    apt-get install -y nginx
    systemctl enable --now nginx
    echo "<h1>Hello from Terraform nginx</h1>" > /var/www/html/index.html
  EOF
}

resource "aws_eip" "server_ip" {
  instance = aws_instance.myserver.id
  domain   = "vpc"
}