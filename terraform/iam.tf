# AWS Batch Service Role
resource "aws_iam_role" "batch_service_role" {
  name = "BatchServiceRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "batch.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "batch_service_role" {
  role       = aws_iam_role.batch_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole"
}

# AWS Spot Fleet Role for Batch
resource "aws_iam_role" "spot_fleet_role" {
  name = "AmazonEC2SpotFleetRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "spotfleet.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "spot_fleet_role_policy" {
  role       = aws_iam_role.spot_fleet_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2SpotFleetTaggingRole"
}

# ECR Access Policy
resource "aws_iam_policy" "s3_ecr_policy" {
  name        = "S3ECRPolicy"
  description = "Policy to allow access to the S3 bucket used by ECR"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "arn:aws:s3:::prod-${var.aws_region}-starport-layer-bucket/*"
      }
    ]
  })
}

# EC2 Instance Role - Reused for Batch compute resources
resource "aws_iam_role" "ec2_instance_role" {
  name        = "ec2InstanceRole"  # Keep the same name for compatibility
  description = "Role used by EC2 instances for Batch compute environments"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}


resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "ec2InstanceProfile"
  role = aws_iam_role.ec2_instance_role.name
}

# EC2 permissions for SSM access
resource "aws_iam_role_policy_attachment" "ec2_ssm_manager" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# S3 model access for EC2 instances
resource "aws_iam_policy" "ec2_s3_model_access" {
  name        = "EC2S3ModelAccess"
  description = "Policy to allow EC2 instances to access model files in S3"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          "arn:aws:s3:::${aws_s3_bucket.model_bucket.bucket}",
          "arn:aws:s3:::${ aws_s3_bucket.model_bucket.bucket}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_s3_model_access" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = aws_iam_policy.ec2_s3_model_access.arn
}

# EC2 describe instances policy
resource "aws_iam_policy" "ec2_describe_instances" {
  name        = "EC2DescribeInstancesPolicy"
  description = "Allow EC2 DescribeInstances for container agents"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_describe_instances_attach" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = aws_iam_policy.ec2_describe_instances.arn
}

# Add ECR readonly access for EC2 instances
data "aws_iam_policy" "ecr_readonly" {
  arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "ec2_ecr_readonly" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = data.aws_iam_policy.ecr_readonly.arn
}

# Add CloudWatch Logs access for EC2 instances
resource "aws_iam_role_policy_attachment" "ec2_cloudwatch_logs" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

# Batch Job Role - For the container itself
resource "aws_iam_role" "batch_job_role" {
  name        = "BatchJobRole"
  description = "Role used by containers in Batch jobs to access AWS services"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

# Reuse the S3 access for the job role
resource "aws_iam_role_policy_attachment" "batch_job_s3_access" {
  role       = aws_iam_role.batch_job_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

# Reuse the EC2 describe instances policy for the job role
resource "aws_iam_role_policy_attachment" "batch_job_ec2_describe" {
  role       = aws_iam_role.batch_job_role.name
  policy_arn = aws_iam_policy.ec2_describe_instances.arn
}

# Add CloudWatch logging for the job role
resource "aws_iam_role_policy_attachment" "batch_job_cloudwatch" {
  role       = aws_iam_role.batch_job_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

# Allow the batch job role to register with service discovery
resource "aws_iam_policy" "service_discovery_policy" {
  name        = "ServiceDiscoveryPolicy"
  description = "Allow containers to register with AWS Cloud Map"
  
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "servicediscovery:RegisterInstance",
          "servicediscovery:DeregisterInstance",
          "servicediscovery:DiscoverInstances",
          "servicediscovery:GetNamespace",
          "servicediscovery:GetService",
          "servicediscovery:GetInstance",
          "servicediscovery:ListInstances"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "route53:CreateHealthCheck",
          "route53:DeleteHealthCheck",
          "route53:GetHealthCheck",
          "route53:UpdateHealthCheck",
          "route53:ChangeResourceRecordSets"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "batch_job_service_discovery" {
  role       = aws_iam_role.batch_job_role.name
  policy_arn = aws_iam_policy.service_discovery_policy.arn
}

# SSM permissions for the batch job role
resource "aws_iam_role_policy_attachment" "batch_job_ssm" {
  role       = aws_iam_role.batch_job_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"
}

# Policy for EC2 instances to join the ECS cluster (needed for Batch)
resource "aws_iam_role_policy_attachment" "ec2_ecs_policy" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# CloudWatch Events role for Batch job scheduling
resource "aws_iam_role" "events_role" {
  name = "EventsInvokeBatchJobsRole"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "events.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "events_batch_policy" {
  name = "EventsInvokeBatchJobsPolicy"
  role = aws_iam_role.events_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "batch:SubmitJob"
      ]
      Resource = "*"
    }]
  })
}