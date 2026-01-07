###################################
###### EC2 Launch Template  #######
###################################

data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}

resource "aws_launch_template" "pestpp_host_setup" {
  name          = "pestpp-host-setup"
  description   = "Launch template for PESTPP model environment setup"

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2_instance_profile.arn
  }

  # script runs when the EC2 instance starts
  user_data = base64encode(<<-EOT
Content-Type: multipart/mixed; boundary="==MYBOUNDARY=="
MIME-Version: 1.0

--==MYBOUNDARY==
Content-Type: text/cloud-config; charset="us-ascii"

#cloud-config
repo_update: true
repo_upgrade: all

--==MYBOUNDARY==
Content-Type: text/x-shellscript; charset="us-ascii"

#!/bin/bash
# Create model directory on host
sudo mkdir -p /pestpp/model

# Download model files from S3
aws s3 sync s3://${aws_s3_bucket.model_bucket.bucket}/model/ /pestpp/model/ --region ${var.aws_region}

# Set permissions
sudo chmod -R 777 /pestpp/model

--==MYBOUNDARY==--
EOT
  )
}

###################################
#######  PESTPP MANAGER  ##########
###################################

resource "aws_batch_compute_environment" "pestpp_ondemand" {
  name                     = "pestpp-manager-ondemand"
  service_role             = aws_iam_role.batch_service_role.arn
  type                     = "MANAGED"
  
  compute_resources {
    type                = "EC2"  # Using on-demand instances
    allocation_strategy = "BEST_FIT_PROGRESSIVE"
    
    max_vcpus     = 4     # how many vcpus the compute env. can support
    min_vcpus     = 0     # Scale to zero when not in use
    desired_vcpus = 0    
    
    instance_type = ["m7i.large"]
    
    subnets = aws_subnet.private_subnets[*].id
    security_group_ids = [aws_security_group.main.id]
    
    instance_role = aws_iam_instance_profile.ec2_instance_profile.arn
    
    ec2_configuration {
      image_id_override = data.aws_ssm_parameter.ecs_ami.value
      image_type = "ECS_AL2023"
    }    
    
    launch_template {
      launch_template_id = aws_launch_template.pestpp_host_setup.id
      version            = "$Latest"
    }


    tags = merge(
      var.default_tags,
      {
        Name    = "PESTPP-Manager-Ondemand",
        Service = "AWS Batch Compute Environment",
        Purpose = "Runs PESTPP manager job on on-demand instances"
      }
    )

  }
  
  lifecycle {
    create_before_destroy = false
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.batch_service_role,
    aws_iam_role_policy_attachment.ec2_ecr_readonly,
    aws_iam_role_policy_attachment.ec2_s3_model_access,
    aws_launch_template.pestpp_host_setup    
  ]

  tags = merge(
    var.default_tags,
    {
      Name    = "PESTPP-Batch-OnDemand-Env",
      Service = "AWS Batch",
      Purpose = "Manages on-demand resources for PESTPP manager"
    }
  )
}

resource "aws_batch_job_queue" "pestpp_manager_queue" {
  name     = "pestpp-manager-queue"
  state    = "ENABLED"
  priority = 100

  compute_environment_order {
    order               = 1
    compute_environment = aws_batch_compute_environment.pestpp_ondemand.arn
  }

  lifecycle {
    create_before_destroy = true
  }
  
  tags = merge(
    var.default_tags,
    {
      Name    = "PESTPP-Manager-Queue",
      Service = "AWS Batch",
      Purpose = "Queues PESTPP manager jobs on on-demand instances"
    }
  )
}

resource "aws_batch_job_definition" "pestpp_manager" {
  name = "pestpp-manager"
  type = "container"
  
  platform_capabilities = ["EC2"]
  
  retry_strategy {
    attempts = 3  # Only retry if the instance is terminated
    
    # Only retry on host termination (spot instance reclaimed)
    evaluate_on_exit {
      action           = "RETRY"
      on_status_reason = "Host EC2*"
    }
    
    # Don't retry on normal completion or application errors
    evaluate_on_exit {
      action    = "EXIT"
      on_reason = "*"
    }
  }
  
  container_properties = jsonencode({
    image = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/pestpp:latest",
    networkMode = "awsvpc",
    resourceRequirements = [
      {
        type  = "VCPU"
        value = "2"
      },
      {
        type  = "MEMORY"
        value = "4096"
      }
    ],
    
    jobRoleArn = aws_iam_role.batch_job_role.arn,
    
    environment = [
      {
        name = "AWS_REGION"
        value = var.aws_region
      },
      {
        name  = "ROLE"
        value = "manager"
      },
      {
        name  = "PESTPP_BINARY"
        value = "pestpp-swp"
      },
      {
        name  = "CONTROL_FILE"
        value = "sagehen_mf6.pst"
      },
      {
        name  = "S3_BUCKET_NAME"
        value = aws_s3_bucket.model_bucket.bucket
      },
      {
        name  = "MODEL_DIR"
        value = "/pestpp/model"
      }
    ],
    
    mountPoints = [
      {
        containerPath = "/pestpp/model",
        readOnly      = false,
        sourceVolume  = "pestpp-model-volume"
      }
    ],
    
    volumes = [
      {
        name = "pestpp-model-volume",
        host = {
          sourcePath = "/pestpp/model"
        }
      }
    ],
    
    logConfiguration = {
      logDriver = "awslogs",
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.batch_log_group.name,
        "awslogs-region"        = var.aws_region,
        "awslogs-stream-prefix" = "pestpp-manager"
      }
    },
    
    privileged = false,
    readonlyRootFilesystem = false
  })
  
  tags = merge(
    var.default_tags,
    {
      Name    = "PESTPP-Manager-Job-Definition",
      Service = "AWS Batch",
      Purpose = "Defines how to run the PESTPP manager job"
    }
  )
}

###################################
########  PESTPP WORKER  ##########
###################################

resource "aws_batch_compute_environment" "pestpp_worker" {
  name                     = "pestpp-worker-${lower(var.worker_compute_type)}"
  service_role             = aws_iam_role.batch_service_role.arn
  type                     = "MANAGED"

  compute_resources {
    type                = var.worker_compute_type
    allocation_strategy = var.worker_compute_type == "SPOT" ? "SPOT_CAPACITY_OPTIMIZED" : "BEST_FIT_PROGRESSIVE"
    bid_percentage      = var.worker_compute_type == "SPOT" ? 100 : null
    
    max_vcpus     = var.model_count * 2  # how many vcpus the compute env. can support
    min_vcpus     = 0                    # scale to zero when not in use
    desired_vcpus = 0
    
    instance_type = [
                 "m7i.large", 
                 "m6i.large",
                 "r7i.large",
                 "r6i.large",
                  ]
    
    subnets = aws_subnet.private_subnets[*].id
    security_group_ids = [aws_security_group.main.id]
    
    instance_role = aws_iam_instance_profile.ec2_instance_profile.arn
    
    spot_iam_fleet_role = var.worker_compute_type == "SPOT" ? aws_iam_role.spot_fleet_role.arn : null
    
    ec2_configuration {
      image_id_override = data.aws_ssm_parameter.ecs_ami.value
      image_type = "ECS_AL2023"
    }  

    launch_template {
      launch_template_id = aws_launch_template.pestpp_host_setup.id
      version            = "$Latest"
    }    
    
    tags = merge(
      var.default_tags,
      {
        Name    = "PESTPP-Worker-${var.worker_compute_type}",
        Service = "AWS Batch Compute Environment",
        Purpose = "Runs PESTPP workloads on ${lower(var.worker_compute_type)} instances"
      }
    )
  }

  depends_on = [
    aws_iam_role_policy_attachment.batch_service_role,
    aws_iam_role_policy_attachment.ec2_ecr_readonly,
    aws_iam_role_policy_attachment.ec2_s3_model_access,
    aws_launch_template.pestpp_host_setup
  ]
  
  lifecycle {
    create_before_destroy = false
  }

  tags = merge(
    var.default_tags,
    {
      Name    = "PESTPP-Batch-Compute-Env",
      Service = "AWS Batch",
      Purpose = "Manages compute resources for PESTPP workloads"
    }
  )
}

# Job queue for workers (spot)
resource "aws_batch_job_queue" "pestpp_worker_queue" {
  name     = "pestpp-worker-queue"
  state    = "ENABLED"
  priority = 100

  compute_environment_order {
    order               = 1
    compute_environment = aws_batch_compute_environment.pestpp_worker.arn
  }

  tags = merge(
    var.default_tags,
    {
      Name    = "PESTPP-Worker-Queue",
      Service = "AWS Batch",
      Purpose = "Queues PESTPP worker jobs on ${lower(var.worker_compute_type)} instances"
    }
  )

  lifecycle {
    create_before_destroy = true
  } 
   
}

# Job definition for PESTPP worker
resource "aws_batch_job_definition" "pestpp_worker" {
  name = "pestpp-worker"
  type = "container"
  
  platform_capabilities = ["EC2"]
  
  retry_strategy {
    attempts = 3  # Only retry if the instance is terminated
    
    # Only retry on host termination (spot instance reclaimed)
    evaluate_on_exit {
      action           = "RETRY"
      on_status_reason = "Host EC2*"
    }
    
    # Don't retry on normal completion or application errors
    evaluate_on_exit {
      action    = "EXIT"
      on_reason = "*"
    }
  }
  
  container_properties = jsonencode({
    image = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/pestpp:latest",
    networkMode = "bridge",
    resourceRequirements = [
      {
        type  = "VCPU"
        value = "2"
      },
      {
        type  = "MEMORY"
        value = "4096"
      }
    ],
    
    jobRoleArn = aws_iam_role.batch_job_role.arn,
    
    environment = [
      {
        name = "AWS_REGION"
        value = var.aws_region
      },
      {
        name  = "ROLE"
        value = "worker"
      },
      {
        name  = "PESTPP_BINARY"
        value ="pestpp-swp"
      },
      {
        name  = "CONTROL_FILE"
        value = "sagehen_mf6.pst"
      },
      {
        name  = "S3_BUCKET_NAME"
        value = aws_s3_bucket.model_bucket.bucket
      },
      {
        name  = "MODEL_DIR"
        value = "/pestpp/model"
      },
      {
        name  = "MANAGER_HOST"
        value = "MANAGER_IP_PLACEHOLDER" # This will be replaced at job submission
      }
    ],
    
    mountPoints = [
      {
        containerPath = "/pestpp/model"
        readOnly      = false,
        sourceVolume  = "pestpp-model-volume"
      }
    ],
    
    volumes = [
      {
        name = "pestpp-model-volume",
        host = {
          sourcePath = "/pestpp/model"
        }
      }
    ],
    
    logConfiguration = {
      logDriver = "awslogs",
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.batch_log_group.name,
        "awslogs-region"        = var.aws_region,
        "awslogs-stream-prefix" = "pestpp-worker"
      }
    },
    
    privileged = false,
    readonlyRootFilesystem = false
  })
  
  tags = merge(
    var.default_tags,
    {
      Name    = "PESTPP-Worker-Job-Definition",
      Service = "AWS Batch",
      Purpose = "Defines how to run the PESTPP worker jobs"
    }
  )
}
