# ---------------------------------------------------------------------------------------------------------------------
# Vault Server Outputs
# ---------------------------------------------------------------------------------------------------------------------
output "Load_Balancer_HTTP_Address" {
  value = "http://${aws_lb.alb.dns_name}"
}

# ---------------------------------------------------------------------------------------------------------------------
# PetClinic Web Server Output
# ---------------------------------------------------------------------------------------------------------------------
output "Web_Server_Public_IP" {
  value = aws_instance.website.public_ip
}

output "Web_Server_HTTP_Address" {
  value = "http://${aws_instance.website.public_ip}:8080"
}

# ---------------------------------------------------------------------------------------------------------------------
# MySql Outputs
# ---------------------------------------------------------------------------------------------------------------------
output "MySql_Url" {
  value = "jdbc:mysql://${aws_instance.mysqlserver.private_ip}:3306/${var.db_name}"
}

output "MySQL_Host_IP" {
  value = aws_instance.mysqlserver.private_ip
}

output "MySQL_DB_Name" {
  value = var.db_name
}

