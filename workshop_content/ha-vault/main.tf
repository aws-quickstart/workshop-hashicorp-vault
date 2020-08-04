# ---------------------------------------------------------------------------------------------------------------------
# Randon String Generator
# ---------------------------------------------------------------------------------------------------------------------
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
# VAULT SERVER INSTANCES LAUNCH TEMPLATE
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_launch_template" "vault_instance" {
  name_prefix            = "${var.stack}-lt-"
  image_id               = data.aws_ami.ubuntu.id
  instance_type          = var.client_instance_type
  key_name               = var.keyPairName
  vpc_security_group_ids = [aws_security_group.vault-server_sg.id]

  iam_instance_profile {
    arn = aws_iam_instance_profile.vault-server.arn
  }

  tag_specifications {
    resource_type = "instance"

    tags = merge(
      { "Name" = "${var.stack}-vault-server" },
      { "Project" = var.stack }
    )
  }

  tag_specifications {
    resource_type = "volume"

    tags = merge(
      { "Name" = "${var.stack}-vault-server-volume" },
      { "Project" = var.stack }
    )
  }

  tags = merge(
    { "Name" = "${var.stack}-vault-server-lt" },
    { "Project" = var.stack }
  )

  user_data = base64encode(templatefile("${path.module}/templates/vault-servers.tpl", {
    vault_secrets_id     = aws_secretsmanager_secret.vault-secrets.arn
    aws_region           = var.aws_region
    vault_dns            = aws_lb.alb.dns_name
    kms_key              = "${aws_kms_key.vault_unseal.id}"
    mysql_endpoint       = aws_instance.mysqlserver.private_ip
    db_user              = var.db_user
    db_password          = var.db_password
    role_arn             = aws_iam_role.vault-client.arn
    gremlin_team_id      = var.gremlin_team_id
    gremlin_team_secret  = var.gremlin_secret_key
    gremlin_identifier   = "${var.stack} vault-server"
    vault_dynamodb_table = var.dynamodb_table_name
    vault_log_group      = aws_cloudwatch_log_group.vault_log_group.name
    vault_log_stream     = aws_cloudwatch_log_stream.vault_log_stream.name
  }))
}

resource "aws_kms_key" "vault_unseal" {
  description             = "Vault unseal key"
  deletion_window_in_days = 10

  tags = {
    Name = "vault-kms-unseal-${var.stack}-vault-server-${random_id.rand.hex}"
  }
}

resource "aws_kms_alias" "vault_alias" {
  name          = "alias/vault-kms-unseal-${var.stack}-vault-server-${random_id.rand.hex}"
  target_key_id = aws_kms_key.vault_unseal.key_id
}

resource "aws_secretsmanager_secret" "vault-secrets" {
  name = "${var.stack}-vault-secrets-${random_id.rand.hex}"
}

resource "aws_dynamodb_table" "vault_storage" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "Path"
  range_key    = "Key"

  attribute {
    name = "Path"
    type = "S"
  }

  attribute {
    name = "Key"
    type = "S"
  }

  tags = {
    Name    = var.dynamodb_table_name
    Project = var.stack
  }
}

resource "aws_cloudwatch_log_group" "vault_log_group" {
  name = "${var.stack}-vault-log-group-${random_id.rand.hex}"

  tags = {
    Name    = "${var.stack}-vault-log-group"
    Project = var.stack
  }
}

resource "aws_cloudwatch_log_stream" "vault_log_stream" {
  name           = "${var.stack}-vault-log-stream-${random_id.rand.hex}"
  log_group_name = aws_cloudwatch_log_group.vault_log_group.name
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
  depends_on                  = [aws_instance.mysqlserver, aws_autoscaling_group.vault-asg]

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
    aws_region        = var.aws_region
    web_log_group     = aws_cloudwatch_log_group.web_log_group.name
    web_log_stream    = aws_cloudwatch_log_stream.web_log_stream.name
    vault_server_addr = aws_lb.alb.dns_name
    mysql_endpoint    = aws_instance.mysqlserver.private_ip
    db_name           = var.db_name
    db_user           = var.db_user
    db_password       = var.db_password
  }
}

resource "aws_cloudwatch_log_group" "web_log_group" {
  name = "${var.stack}-web-log-group-${random_id.rand.hex}"

  tags = {
    Name    = "${var.stack}-web-log-group"
    Project = var.stack
  }
}

resource "aws_cloudwatch_log_stream" "web_log_stream" {
  name           = "${var.stack}-web-log-stream-${random_id.rand.hex}"
  log_group_name = aws_cloudwatch_log_group.web_log_group.name
}