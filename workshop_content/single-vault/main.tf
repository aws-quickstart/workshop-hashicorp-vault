# ---------------------------------------------------------------------------------------------------------------------
# Randon String Generator
# ---------------------------------------------------------------------------------------------------------------------
#
resource "random_id" "rand" {
  byte_length = 4
}


# ---------------------------------------------------------------------------------------------------------------------
# DATA FOR AMI
# ---------------------------------------------------------------------------------------------------------------------
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}


# ---------------------------------------------------------------------------------------------------------------------
# MYSQL Server
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_instance" "mysqlserver" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.client_instance_type
  user_data                   = data.template_file.mysqlserver.rendered
  subnet_id                   = aws_subnet.private[1].id
  key_name                    = var.keyPairName
  vpc_security_group_ids      = [aws_security_group.db-sg.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.vault-client.id

  ebs_block_device {
    device_name = "/dev/sda1"
    volume_type = "gp2"
    volume_size = "60"
  }
  tags = {
    Name    = "${var.stack}-mysql-server"
    Project = var.stack
  }
}

data "template_file" "mysqlserver" {
  template = file("${path.module}/templates/mysqlserver.tpl")
}


# ---------------------------------------------------------------------------------------------------------------------
# VAULT SERVER INSTANCE
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_instance" "vault-server" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.client_instance_type
  user_data                   = data.template_file.setup-vault.rendered
  subnet_id                   = aws_subnet.public[0].id
  key_name                    = var.keyPairName
  vpc_security_group_ids      = [aws_security_group.vault-server_sg.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.vault-server.id
  depends_on                  = [aws_instance.mysqlserver]


  ebs_block_device {
    device_name = "/dev/sda1"
    volume_type = "gp2"
    volume_size = "60"
  }
  tags = {
    Name    = "${var.stack}-vault-server"
    Project = var.stack
  }

}

data "template_file" "setup-vault" {
  template = file("${path.module}/templates/vault-server.tpl")

  vars = {
    vault_secrets_id    = aws_secretsmanager_secret.vault-secrets.arn
    aws_region          = var.aws_region
    kms_key             = "${aws_kms_key.vault_unseal.id}"
    mysql_endpoint      = aws_instance.mysqlserver.private_ip
    db_user             = var.db_user
    db_password         = var.db_password
    role_arn            = aws_iam_role.vault-client.arn
    gremlin_team_id     = var.gremlin_team_id
    gremlin_team_secret = var.gremlin_secret_key
    gremlin_identifier  = "${var.stack} vault-server"
  }
}

resource "aws_kms_key" "vault_unseal" {
  description             = "Vault unseal key"
  deletion_window_in_days = 10

  tags = {
    Name = "vault-kms-unseal-${var.stack}-vault-server"
  }
}

resource "aws_kms_alias" "vault_alias" {
  name          = "alias/vault-kms-unseal-${var.stack}-vault-server"
  target_key_id = aws_kms_key.vault_unseal.key_id
}

resource "aws_secretsmanager_secret" "vault-secrets" {
  name = "${var.stack}-vault-secrets-${random_id.rand.hex}"
}

# ---------------------------------------------------------------------------------------------------------------------
# WEBSITE INSTANCE
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_instance" "website" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.client_instance_type
  user_data                   = data.template_file.website.rendered
  subnet_id                   = aws_subnet.public[1].id
  key_name                    = var.keyPairName
  vpc_security_group_ids      = [aws_security_group.vault-client_sg.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.vault-client.id
  depends_on                  = [aws_instance.mysqlserver, aws_instance.vault-server]

  ebs_block_device {
    device_name = "/dev/sda1"
    volume_type = "gp2"
    volume_size = "60"
  }
  tags = {
    Name    = "${var.stack}-web-server"
    Project = var.stack
  }
}

data "template_file" "website" {
  template = file("${path.module}/templates/petclinic-app.tpl")

  vars = {
    vault_server_addr = aws_instance.vault-server.private_ip
    mysql_endpoint    = aws_instance.mysqlserver.private_ip
    db_name           = var.db_name
    db_user           = var.db_user
    db_password       = var.db_password
  }
}

