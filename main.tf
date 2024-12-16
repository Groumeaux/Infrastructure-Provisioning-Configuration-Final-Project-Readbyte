#AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.69.0"
    }
  }
  # project_VPC is the version of Terraform we will use
  required_version = ">= 1.9.6"
}

provider "aws" {
  region = "us-east-1"
}

# ----------------------------------------------------------------------------------------------------------------------------------------

# Generate new private key 
resource "tls_private_key" "my_key" {
  algorithm = "RSA"
}

# Generate a key-pair with above key
resource "aws_key_pair" "deployer" {
  key_name   = "key_project"
  public_key = tls_private_key.my_key.public_key_openssh
}

# Saving Key Pair
resource "local_file" "private_key" {
  content         = tls_private_key.my_key.private_key_pem
  filename        = "key_project.pem"
  file_permission = "0400"
}

# ----------------------------------------------------------------------------------------------------------------------------------------

#vpc
resource "aws_vpc" "project_VPC" {
  cidr_block = "10.100.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "project-vpc"
  }
}

#public subnets
resource "aws_subnet" "public1" {
  vpc_id                  = aws_vpc.project_VPC.id
  cidr_block              = "10.100.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "project-public-1"
  }
}

resource "aws_subnet" "public2" {
  vpc_id                  = aws_vpc.project_VPC.id
  cidr_block              = "10.100.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "project-public-2"
  }
}

#private subnets
resource "aws_subnet" "private1" {
  vpc_id            = aws_vpc.project_VPC.id
  cidr_block        = "10.100.3.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "project-private-1"
  }
}
resource "aws_subnet" "private2" {
  vpc_id            = aws_vpc.project_VPC.id
  cidr_block        = "10.100.4.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "project-private-2"
  }
}

# ----------------------------------------------------------------------------------------------------------------------------------------

#internet gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.project_VPC.id

  tags = {
    Name = "project-igw"
  }
}

# Elastic IP
resource "aws_eip" "eip" {
  domain = "vpc"
}

# NAT Gateway
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.eip.id
  subnet_id     = aws_subnet.public1.id

  tags = {
    Name = "project-nat"
  }
}

#public route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.project_VPC.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-rt"
  }
}

#private route table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.project_VPC.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "private-rt"
  }
}

# ----------------------------------------------------------------------------------------------------------------------------------------

#route table association
resource "aws_route_table_association" "public1" {
  subnet_id      = aws_subnet.public1.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "public2" {
  subnet_id      = aws_subnet.public2.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "private1" {
  subnet_id      = aws_subnet.private1.id
  route_table_id = aws_route_table.private.id
}
resource "aws_route_table_association" "private2" {
  subnet_id      = aws_subnet.private2.id
  route_table_id = aws_route_table.private.id
}

#security group
resource "aws_security_group" "projectSG" {
  name        = "projectSG"
  description = "Allow SSH inbound traffic"
  vpc_id      = aws_vpc.project_VPC.id

  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTP"
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow MYSQL"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.100.0.0/16"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "projectSG"
  }
}

# -----------------------------------------------------------------------------------------------------------------------------------------

# EC2
resource "aws_instance" "php-app" {
  ami                         = "ami-06d745489a64b315e"
  instance_type               = "t2.medium"
  key_name                    = aws_key_pair.deployer.key_name
  subnet_id                   = aws_subnet.public1.id
  security_groups             = [aws_security_group.projectSG.id]
  associate_public_ip_address = true

  tags = {
    Name = "project-akhir"
  }

}

# rds subnet
resource "aws_db_subnet_group" "rds_subnet_group-project" {
  name       = "rds-subnet-group-project"
  subnet_ids = [aws_subnet.private1.id, aws_subnet.private2.id]

}
resource "aws_db_instance" "rds_instance" {
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  identifier             = "my-final-rds-instance"
  db_name                = "data_perpus"
  username               = "projectseal"
  password               = "final123"
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group-project.name
  vpc_security_group_ids = [aws_security_group.rds_security_group.id]
  multi_az               = true
  skip_final_snapshot    = true

  tags = {
    Name = "RDS Instance"
  }
}


# RDS security group
resource "aws_security_group" "rds_security_group" {
  name        = "rds-security-group"
  description = "Security group for RDS instance"
  vpc_id      = aws_vpc.project_VPC.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.100.0.0/16"]
  }

  tags = {
    Name = "RDS Security Group"
  }
}

# -----------------------------------------------------------------------------------------------------------------------------------------


resource "aws_cloudwatch_metric_alarm" "cpu_utilization_high" {
  alarm_name          = "RDSHighCPUUtilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.rds_instance.id
  }

  alarm_description = "This metric monitors RDS CPU Utilization"
  alarm_actions     = [aws_sns_topic.alarm_email.arn] 
}

resource "aws_cloudwatch_metric_alarm" "free_storage_space_low" {
  alarm_name          = "RDSLowFreeStorageSpace"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 5000000000

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.rds_instance.id
  }

  alarm_description = "This metric monitors RDS Free Storage Space"
  alarm_actions     = [aws_sns_topic.alarm_email.arn] 
}


resource "aws_sns_topic" "alarm_email" {
  name         = "my-sns-topic"
  display_name = "RDS Alarm Notifications"
}


resource "aws_sns_topic_subscription" "alarm_to_email" {
  topic_arn = aws_sns_topic.alarm_email.arn
  protocol  = "email"
  endpoint  = "juventinopalandeng@gmail.com"
}

output "rds_endpoint" {
  value = aws_db_instance.rds_instance.endpoint
}

output "ec2_public_ip" {
  value = aws_instance.php-app.public_ip
}
