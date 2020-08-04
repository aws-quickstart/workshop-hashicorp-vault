
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

variable "private_mode" {
  description = "Whether or not the Vault deployment should be private."
  type        = bool
  default     = false
}

variable "allowed_traffic_cidr_blocks" {
  description = "List of CIDR blocks allowed to send requests to your vault endpoint.  Defaults to EVERYWHERE.  You should probably limit this to your organization IP or VPC CIDR."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "vault_instance_count" {
  description = "The number of EC2 instances to launch as vault instances.  Should be no less than 2."
  type        = number
  default     = 2
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB Table used for the Vault Storage Backend."
  type        = string
  default     = "vault_storage"
}

variable "stack" {
  description = "Name of the stack."
  default     = "Vault-Workshop"
}

variable "db_name" {
  description = "MySQL DB name"
  default     = "petclinic"
}

variable "db_user" {
  description = "MySQL DB username"
  default     = "root"
}

variable "db_password" {
  description = "Mysql DB password"
  default     = "ech9Weith4Phei7W"
}