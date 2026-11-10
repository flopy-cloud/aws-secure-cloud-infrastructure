resource "aws_db_subnet_group" "main" {
  name       = "secure-db-subnets"
  subnet_ids = aws_subnet.private[*].id
  tags       = { Name = "secure-db-subnets" }
}

resource "aws_db_instance" "main" {
  identifier        = "secure-db"
  engine            = "postgres"
  engine_version    = "16"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "appdb"
  username = "dbadmin"
  # AWS genera la contraseña y la guarda en Secrets Manager: no queda en el código
  manage_master_user_password = true

  db_subnet_group_name                = aws_db_subnet_group.main.name
  vpc_security_group_ids              = [aws_security_group.db.id]
  publicly_accessible                 = false
  iam_database_authentication_enabled = true
  multi_az                            = false

  backup_retention_period = 1
  skip_final_snapshot     = true  # para poder hacer terraform destroy
  deletion_protection     = false # idem

  tags = { Name = "secure-db" }
}