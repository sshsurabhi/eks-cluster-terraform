resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-subnet-group"
  subnet_ids = [aws_subnet.private_1.id, aws_subnet.private_2.id]

  tags = {
    Name = "rds-subnet-group"
  }
}

resource "aws_db_instance" "rds_instance" {
  identifier            = "rds-instance"
  engine                = "mysql"
  instance_class        = "db.t3.medium"
  allocated_storage     = 20
  db_name               = "mydb"
  username              = "petclinic"
  password              = "petclinicdbpassword"
  skip_final_snapshot   = true
  multi_az              = true

  vpc_security_group_ids = [aws_security_group.rds_sg.id]  # Attach security group
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
}


