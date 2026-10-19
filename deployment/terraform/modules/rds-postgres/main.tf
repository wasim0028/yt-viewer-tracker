# Private, encrypted PostgreSQL.
#
# Master password: uses var.master_password if you supply one, otherwise a
# generated one. Either way, read it from the "password" output and store it
# in Secrets Manager (see the app-secrets module).
#
# The generated password is always created, even when unused. Choosing with
# count isn't possible: Terraform doesn't allow a sensitive value to decide
# whether a resource exists.

resource "random_password" "master" {
  length  = 32
  special = true
  # Excludes / @ " and space, which RDS rejects in master passwords.
  override_special = "!#$%^&*()-_=+[]{}<>:?"
}

locals {
  master_password = coalesce(var.master_password, random_password.master.result)
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.identifier}-subnets"
  subnet_ids = var.private_subnet_ids
}

resource "aws_security_group" "this" {
  name        = "${var.identifier}-sg"
  description = "PostgreSQL access for ${var.identifier}"
  vpc_id      = var.vpc_id
}

# count (not for_each): the security group IDs usually aren't known until
# apply, and for_each can't use unknown values as keys.
resource "aws_security_group_rule" "ingress" {
  count                    = length(var.allowed_security_group_ids)
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.this.id
  source_security_group_id = var.allowed_security_group_ids[count.index]
  description              = "PostgreSQL from allowed security group"
}

resource "aws_db_instance" "this" {
  identifier     = var.identifier
  engine         = "postgres"
  engine_version = var.engine_version

  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage_gb
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.username
  password = local.master_password

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  publicly_accessible    = false
  multi_az               = var.multi_az

  backup_retention_period   = var.backup_retention_days
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.identifier}-final-snapshot"
}
