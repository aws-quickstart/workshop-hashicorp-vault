//--------------------------------------------------------------------
// Resources

## Vault Server IAM Config
resource "aws_iam_instance_profile" "vault-server" {
  name = "${var.stack}-vault-server-instance-profile-${random_id.rand.hex}"
  role = aws_iam_role.vault-server.name
}

resource "aws_iam_role" "vault-server" {
  name               = "${var.stack}-vault-server-role-${random_id.rand.hex}"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy" "vault-server" {
  name   = "${var.stack}-vault-server-role-policy-${random_id.rand.hex}"
  role   = aws_iam_role.vault-server.id
  policy = data.aws_iam_policy_document.vault-server.json
}

# Vault Client IAM Config
resource "aws_iam_instance_profile" "vault-client" {
  name = "${var.stack}-vault-client-instance-profile-${random_id.rand.hex}"
  role = aws_iam_role.vault-client.name
}

resource "aws_iam_role" "vault-client" {
  name               = "${var.stack}-vault-client-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy" "vault-client" {
  name   = "${var.stack}-vault-client-role-policy-${random_id.rand.hex}"
  role   = aws_iam_role.vault-client.id
  policy = data.aws_iam_policy_document.vault-client.json
}

//--------------------------------------------------------------------
// Data Sources

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "vault-server" {
  statement {
    sid    = "ConsulAutoJoin"
    effect = "Allow"

    actions = ["ec2:DescribeInstances"]

    resources = ["*"]
  }

  statement {
    sid    = "VaultAWSAuthMethod"
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "iam:GetInstanceProfile",
      "iam:GetRole",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "VaultKMSUnseal"
    effect = "Allow"

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:DescribeKey",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "VaultSecretsManager"
    effect = "Allow"

    actions = [
      "secretsmanager:PutSecretValue",
      "secretsmanager:CreateSecret",
      "secretsmanager:UpdateSecret"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "VaultLogsSetup"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]

    resources = ["arn:aws:logs:*:*:*"]
  }

  statement {
    sid    = "VaultCloudWatchSetup"
    effect = "Allow"

    actions = [
      "cloudwatch:PutMetricData",
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:ListMetrics"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "VaultSSM"
    effect = "Allow"

    actions = [
      "ssm:*"
    ]

    resources = ["*"]
  }
}

data "aws_iam_policy_document" "vault-client" {
  statement {
    sid    = "ConsulAutoJoin"
    effect = "Allow"

    actions = ["ec2:DescribeInstances"]

    resources = ["*"]
  }

  statement {
    sid    = "VaultLogsSetup"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]

    resources = ["arn:aws:logs:*:*:*"]
  }

  statement {
    sid    = "VaultCloudWatchSetup"
    effect = "Allow"

    actions = [
      "cloudwatch:PutMetricData",
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:ListMetrics"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "VaultSSM"
    effect = "Allow"

    actions = [
      "ssm:*"
    ]

    resources = ["*"]
  }
}