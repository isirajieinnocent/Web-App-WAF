# AWS Provider
provider "aws" {
  region = "us-east-1"
}

# VPC: A virtual network where all the resources of this project will reside
resource "aws_vpc" "WebApp_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = var.WebApp_vpc # Tag the VPC with the given name
  }
}

# Subnet: Divide the VPC into smaller subnets
# Private Subnet in Availability Zone us-east-1a
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.WebApp_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  
  tags = {
    Name = var.private_a # Tag the subnet for easy identification
  }
}

# Public Subnet in Availability Zone us-east-1b
resource "aws_subnet" "public_b" {
  vpc_id            = aws_vpc.WebApp_vpc.id
  cidr_block        = "10.0.4.0/25"
  availability_zone = "us-east-1b"
  
  tags = {
    Name = var.public_b 
  }
}


# Security Group for the ALB
resource "aws_security_group" "lb_sg" {
  name        = "alb_security_group"
  description = "Allow HTTP and HTTPS inbound traffic to ALB"
  vpc_id      = aws_vpc.WebApp_vpc.id

  # Inbound traffic rules
  ingress {
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  ingress {
    description = "Allow HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound rule to allow all traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "lb_sg"
  }
}


# Create Application Load Balancer (ALB)
resource "aws_lb" "WebAPP_LB" {
  name               = "WebAPP-lb-tf"
  internal           = false 
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg.id]
  subnets            = [aws_subnet.public_b.id]
  enable_deletion_protection = true 
  

  access_logs {
    bucket  = aws_s3_bucket.lb_logs.id # Enable access logging to an S3 bucket
    prefix  = "WebAPP-lb"
    enabled = true
  }

  tags = {
    Environment = "production"
    Name        = var.WebAPP
  }
}



# Create WAF ACL with rules and associate it with the ALB
resource "aws_wafv2_web_acl" "WebAPP_Waf" {
  name        = "WebAPP_Waf"
  scope       = "REGIONAL" # WAF is regional for ALB
  description = "WebAPP Web ACL"
  default_action {
    allow {} # Default action: allow requests that don't match any rule
  }

  rule {
    name     = "IPBlockRule"
    priority = 1  # Rule evaluation order
    action {
      block {} # Block matching requests
    }
    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.Wafv2IPSet.arn # Use IP set for blocking specific IPs
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true # Enable CloudWatch monitoring for this rule
      metric_name                = "IPBlockRule"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true # Enable CloudWatch metrics for the Web ACL
    metric_name                = "WebAPPWAF"
    sampled_requests_enabled   = true
  }
}

# AWS WAF IP Set to block specific IP addresses
resource "aws_wafv2_ip_set" "Wafv2IPSet" {
  name              = "Wafv2IPSet"
  scope             = "REGIONAL" # Regional for ALB
  ip_address_version = "IPV4"

  addresses = [
    "203.0.113.0/24",  # IPs to block
  ]

  tags = {
    Name = "Wafv2IPSet"
  }
}

# AWS WAF Web ACL Association with the ALB
resource "aws_wafv2_web_acl_association" "WebAPP_Waf_Associate" {
  web_acl_arn = aws_wafv2_web_acl.WebAPP_Waf.arn
  resource_arn = aws_lb.WebAPP_LB.arn # Attach WAF ACL to the ALB
}



# Web Application instances in public subnet
resource "aws_instance" "web" {
  count             = 2
  ami               = "ami-070f589e4b4a3fece"  # Replace with your preferred AMI ID
  instance_type     = "t2.micro"
  subnet_id         = aws_subnet.public_b.id # Place in public subnet
  security_groups   = [aws_security_group.lb_sg.id] # Assign the ALB security group
  associate_public_ip_address = true

  tags = {
    Name = "web-instance-${count.index}"
  }

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "<html><body><h1>Hello from instance ${count.index}</h1></body></html>" > /var/www/html/index.html
              EOF
}

# Attach Web Instances to ALB Target Group
resource "aws_lb_target_group_attachment" "web" {
  count            = 2
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.web[count.index].id
  port             = 80
}

# Database Subnet Group for the RDS Instance
resource "aws_db_subnet_group" "webAppDB" {
  name       = "webAppDB-db-subnet-group"
  subnet_ids = [aws_subnet.private_a.id] # Use private subnets

  tags = {
    Name = "webAppDB-db-subnet-group"
  }
}

# MySQL RDS Database Instance
resource "aws_db_instance" "AppDB" {
  allocated_storage    = 10
  db_name              = "mydb"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro"
  username             = "foo"
  password             = "foobarbaz"
  parameter_group_name = "default.mysql8.0"
  skip_final_snapshot  = true
  multi_az             = false
  storage_type         = "gp2"
  publicly_accessible  = false

  tags = {
    Name = "AppDB"
  }
}

# Security Group for MySQL Database
resource "aws_security_group" "mysql_sg" {
  name        = "mysql-security-group"
  description = "Security group for MySQL database"
  vpc_id      = aws_vpc.WebApp_vpc.id

  # Inbound Rule to allow MySQL (Port 3306) from specific IPs or security groups
  ingress {
    description = "Allow MySQL access"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["203.0.113.0/24"] # Replace with trusted IP range
  }

  # Outbound rule - allow all traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "mysql-sg"
  }
}

# Variable for DB Instance
variable "aws_db_instance" {
  description = "The name of the DB instance"
  type        = string
  default     = "AppDB"
}
