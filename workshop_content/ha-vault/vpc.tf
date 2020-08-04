# ---------------------------------------------------------------------------------------------------------------------
# NETWORK DETAILS
# ---------------------------------------------------------------------------------------------------------------------
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------------------------------------------------
provider "aws" {
  region                      = var.aws_region
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_get_ec2_platforms      = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.stack}-VPC"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# PRIVATE SUBNETS
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_subnet" "private" {
  count             = var.az_count
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  vpc_id            = aws_vpc.main.id

  tags = {
    Name = "${var.stack}-PrivateSubnet-${count.index + 1}"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# PUBLIC SUBNETS
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count                   = var.az_count
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, var.az_count + count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  vpc_id                  = aws_vpc.main.id
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.stack}-PublicSubnet-${count.index + 1}"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# INTERNET GATEWAY
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.stack}-IGW"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# ROUTE FOR PUBLIC SUBNETS
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_route" "public-route" {
  route_table_id         = aws_vpc.main.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

# ---------------------------------------------------------------------------------------------------------------------
# INTERNET GATEWAY
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_eip" "eip" {
  count      = var.az_count
  vpc        = true
  depends_on = [aws_internet_gateway.igw]

  tags = {
    Name = "${var.stack}-eip-${count.index + 1}"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# NAT GATEWAY
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_nat_gateway" "nat" {
  count         = var.az_count
  subnet_id     = element(aws_subnet.public.*.id, count.index)
  allocation_id = element(aws_eip.eip.*.id, count.index)

  tags = {
    Name = "${var.stack}-NatGateway-${count.index + 1}"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# PRIVATE ROUTE TABLE
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_route_table" "private-route-table" {
  count  = var.az_count
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = element(aws_nat_gateway.nat.*.id, count.index)
  }

  tags = {
    Name = "${var.stack}-PrivateRouteTable-${count.index + 1}"
  }
}

resource "aws_route_table_association" "route-association" {
  count          = var.az_count
  subnet_id      = element(aws_subnet.private.*.id, count.index)
  route_table_id = element(aws_route_table.private-route-table.*.id, count.index)
}

resource "aws_vpc_dhcp_options" "dhcp_set" {
  domain_name_servers = ["172.17.0.2"]
}

resource "aws_vpc_dhcp_options_association" "dns_resolver" {
  vpc_id          = aws_vpc.main.id
  dhcp_options_id = aws_vpc_dhcp_options.dhcp_set.id
}

# ---------------------------------------------------------------------------------------------------------------------
# DynamoDB Gateway
# ---------------------------------------------------------------------------------------------------------------------
data "aws_vpc_endpoint_service" "dynamodb" {
  service = "dynamodb"
}

resource "aws_vpc_endpoint" "dynamodb" {
  service_name = data.aws_vpc_endpoint_service.dynamodb.service_name
  vpc_id       = aws_vpc.main.id

  // Can also be done with "aws_vpc_endpoint_route_table_association"
  route_table_ids = [aws_route_table.private-route-table.0.id, aws_route_table.private-route-table.1.id]

  tags = merge(
    { "Name" = "${var.stack}-dynamodb-endpoint" },
    { "Project" = var.stack }
  )

  vpc_endpoint_type = "Gateway"
}

# ---------------------------------------------------------------------------------------------------------------------
# Auto-Scaling Group
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_autoscaling_group" "vault-asg" {
  name_prefix = "${var.stack}-asg-"

  launch_template {
    id      = aws_launch_template.vault_instance.id
    version = aws_launch_template.vault_instance.latest_version
  }

  target_group_arns = [aws_lb_target_group.alb_targets.arn]

  # All the same to keep at a fixed size
  desired_capacity = var.vault_instance_count
  min_size         = var.vault_instance_count
  max_size         = var.vault_instance_count

  # AKA the subnets to launch resources in 
  vpc_zone_identifier = [aws_subnet.public.0.id, aws_subnet.public.1.id]

  health_check_grace_period = 300
  health_check_type         = "EC2"
  termination_policies      = ["OldestLaunchTemplate"]
  wait_for_capacity_timeout = 0

  enabled_metrics = [
    "GroupDesiredCapacity",
    "GroupInServiceCapacity",
    "GroupPendingCapacity",
    "GroupMinSize",
    "GroupMaxSize",
    "GroupInServiceInstances",
    "GroupPendingInstances",
    "GroupStandbyInstances",
    "GroupStandbyCapacity",
    "GroupTerminatingCapacity",
    "GroupTerminatingInstances",
    "GroupTotalCapacity",
    "GroupTotalInstances"
  ]

  tags = [
    {
      key                 = "Name"
      value               = "${var.stack}-vault-server"
      propagate_at_launch = true
    },
    {
      key                 = "Project"
      value               = var.stack
      propagate_at_launch = true
    }
  ]
}

# ---------------------------------------------------------------------------------------------------------------------
# Application Load Balancer
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_lb" "alb" {
  // Can't give it a full name_prefix due to 32 character limit on LBs
  // and the fact that Terraform adds a 26 character random bit to the end.
  // https://github.com/terraform-providers/terraform-provider-aws/issues/1666
  name_prefix        = "vault-"
  internal           = var.private_mode
  load_balancer_type = "application"
  security_groups    = [aws_security_group.load_balancer.id]
  subnets            = aws_subnet.public.*.id
  idle_timeout       = 60
  ip_address_type    = "ipv4"

  tags = merge(
    { "Name" = "${var.stack}-alb" },
    { "Project" = var.stack }
  )
}

## Target Group
resource "aws_lb_target_group" "alb_targets" {
  name_prefix          = "vault-"
  port                 = 8200
  protocol             = "HTTP"
  vpc_id               = aws_vpc.main.id
  deregistration_delay = 30
  target_type          = "instance"

  health_check {
    enabled             = true
    interval            = 10
    path                = "/v1/sys/health?activecode=200&standbycode=200&sealedcode=200&uninitcode=200"
    protocol            = "HTTP"
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200-499"
  }

  tags = merge(
    { "Name" = "${var.stack}-tg" },
    { "Project" = var.stack }
  )
}

## Load Balancer Listener
resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_targets.arn
  }
}