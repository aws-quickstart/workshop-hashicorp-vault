variable "gremlin_team_id" {
  description = "Gremlin Team ID "
  type        = string
}

variable "gremlin_secret_key" {
  description = "Gremlin Secret Key "
  type        = string
}

variable "aws_region" {
  description = "The AWS region to create things in."
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR for the VPC"
  default     = "172.17.0.0/16"
}

variable "az_count" {
  description = "Number of AZs to cover in a given AWS region"
  default     = "2"
}

variable "keyPairName" {
  description = "Name of the pem key to use for SSH"
  default     = "workshop"
}

variable "client_instance_type" {
  description = "Client instance type"
  default     = "t2.micro"
}

variable "stack" {
  description = "Name of the stack."
  default     = "Vault-Workshop"
}

variable "db_name" {
  description = "RDS DB name"
  default     = "petclinic"
}

variable "db_user" {
  description = "RDS DB username"
  default     = "root"
}

variable "db_password" {
  description = "Mysql DB password"
  default     = "ech9Weith4Phei7W"
}
