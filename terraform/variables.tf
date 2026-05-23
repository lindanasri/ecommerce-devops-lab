variable "aws_region" {
  default = "us-east-1"
}
variable "vpc_cidr" {
  default = "10.0.0.0/16"
}
variable "public_subnet_cidrs" {
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}
variable "private_subnet_cidrs" {
  default = ["10.0.10.0/24", "10.0.20.0/24"]
}
variable "instance_type" {
  default = "t3.micro"
}
variable "key_name" {
  description = "Nom de ta key pair AWS"
}
variable "instance_count" {
  default = 2
}
