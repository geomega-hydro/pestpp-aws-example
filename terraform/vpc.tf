resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  
  tags = merge(
    var.default_tags,
    {
      Service = "Networking - VPC",
      Purpose = "Hosts PESTPP ECS tasks on Spot instances"
    }
  )  
}

resource "aws_subnet" "private_subnets" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet("10.0.0.0/16", 8, count.index) # 753 usable IPs
  map_public_ip_on_launch = false
  availability_zone       = var.availability_zones[count.index]
  
  tags = merge(
    var.default_tags,
    {
      Service = "Networking - Private Subnet ${count.index + 1}",
      Purpose = "Hosts ECS tasks across multiple AZs"
    }
  )  
}

resource "aws_security_group" "main" {
  vpc_id      = aws_vpc.main.id
  name        = "ec2-spot-sg"
  description = "Security group for ECS/Batch tasks on spot instances"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.default_tags,
    {
      Name    = "PESTPP-SG",
      Service = "Networking - Security Group",
      Purpose = "Controls access for ECS/Batch tasks"
    }
  )
}

resource "aws_route_table" "private_route_tables" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.default_tags,
    {
      Service = "Networking - Route Table ${count.index + 1}",
      Purpose = "Routes traffic for private subnet ${count.index + 1}"
    }
  )
}

resource "aws_route_table_association" "private_subnet_associations" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_tables[count.index].id
}

resource "aws_vpc_endpoint" "s3_endpoint" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private_route_tables[*].id
  
  tags = merge(
    var.default_tags,
    {
      Service = "Networking - VPC Endpoint S3",
      Purpose = "Provides access to S3 for ECS tasks"
    }
  )
}

resource "aws_vpc_endpoint" "ec2" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2"
  subnet_ids          = aws_subnet.private_subnets[*].id 
  security_group_ids  = [aws_security_group.main.id]
  private_dns_enabled = true
  vpc_endpoint_type   = "Interface"

  tags = merge(
    var.default_tags,
    {
      Service = "Networking - VPC Endpoint ECR API",
      Purpose = "Provides access to ECR API for container images"
    }
  )
}

resource "aws_vpc_endpoint" "ecr_endpoint" {
  vpc_id             = aws_vpc.main.id
  service_name       = "com.amazonaws.${var.aws_region}.ecr.api"
  subnet_ids         = aws_subnet.private_subnets[*].id
  security_group_ids = [aws_security_group.main.id]
  vpc_endpoint_type  = "Interface"

  private_dns_enabled = true

  tags = merge(
    var.default_tags,
    {
      Service = "Networking - VPC Endpoint ECR",
      Purpose = "Creates a VPC endpoint for ECR"
    }
  )
}

resource "aws_vpc_endpoint" "ecr_docker_endpoint" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  subnet_ids          = aws_subnet.private_subnets[*].id
  security_group_ids  = [aws_security_group.main.id]
  private_dns_enabled = true
  vpc_endpoint_type   = "Interface"

  tags = merge(
    var.default_tags,
    {
      Service = "Networking - VPC Endpoint ECR Docker",
      Purpose = "Provides access to ECR Docker for container images"
    }
  )
}

resource "aws_vpc_endpoint" "ecs_agent_endpoint" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecs-agent"
  subnet_ids          = aws_subnet.private_subnets[*].id
  security_group_ids  = [aws_security_group.main.id]
  private_dns_enabled = true
  vpc_endpoint_type   = "Interface"

  tags = merge(
    var.default_tags,
    {
      Service = "Networking - VPC Endpoint ECS",
      Purpose = "Provides access to ECS API for task orchestration"
    }
  )
}

resource "aws_vpc_endpoint" "ecs_telemetry_endpoint" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecs-telemetry"
  subnet_ids          = aws_subnet.private_subnets[*].id
  security_group_ids  = [aws_security_group.main.id]
  private_dns_enabled = true
  vpc_endpoint_type   = "Interface"

  tags = merge(
    var.default_tags,
    {
      Service = "Networking - VPC Endpoint ECS Telemetry",
      Purpose = "Creates a VPC endpoint for ECS Telemetry"
    }
  )
}

resource "aws_vpc_endpoint" "ecs_endpoint" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecs"
  subnet_ids          = aws_subnet.private_subnets[*].id
  security_group_ids  = [aws_security_group.main.id]
  private_dns_enabled = true
  vpc_endpoint_type   = "Interface"

  tags = merge(
    var.default_tags,
    {
      Service = "Networking - VPC Endpoint ECS",
      Purpose = "Creates a VPC endpoint for ECS"
    }
  )
}

resource "aws_vpc_endpoint" "cloudwatch_logs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  subnet_ids          = aws_subnet.private_subnets[*].id
  security_group_ids  = [aws_security_group.main.id]
  private_dns_enabled = true
  vpc_endpoint_type   = "Interface"

  tags = merge(
    var.default_tags,
    {
      Service = "Networking - VPC Endpoint CloudWatch Logs",
      Purpose = "Provides access to CloudWatch Logs for container logging"
    }
  )
}
