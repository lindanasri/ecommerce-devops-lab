terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# ── Utilise le VPC existant ─────────────────────────────
data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = ["ecommerce-vpc"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

# ── Utilise les subnets existants ───────────────────────
data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
  filter {
    name   = "map-public-ip-on-launch"
    values = ["true"]
  }
}

# ── Security Group ALB ─────────────────────────────────
resource "aws_security_group" "alb_sg" {
  name   = "alb-sg-pipeline"
  vpc_id = data.aws_vpc.main.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "alb-sg-pipeline" }
}

# ── Security Group EC2 ─────────────────────────────────
resource "aws_security_group" "ec2_sg" {
  name   = "ec2-sg-pipeline"
  vpc_id = data.aws_vpc.main.id
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }
  ingress {
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
  tags = { Name = "ec2-sg-pipeline" }
}

# ── EC2 Instances ──────────────────────────────────────
resource "aws_instance" "web" {
  count                  = var.instance_count
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = tolist(data.aws_subnets.public.ids)[count.index % length(data.aws_subnets.public.ids)]
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  tags = { Name = "web-pipeline-${count.index + 1}" }
}

# ── ALB ────────────────────────────────────────────────
resource "aws_lb" "alb" {
  name               = "ecommerce-alb-pipeline"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = tolist(data.aws_subnets.public.ids)
  tags = { Name = "ecommerce-alb-pipeline" }
}

resource "aws_lb_target_group" "tg" {
  name     = "ecommerce-tg-pipeline"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.main.id
  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
  }
}

resource "aws_lb_target_group_attachment" "tg_attach" {
  count            = var.instance_count
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.web[count.index].id
  port             = 80
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}
