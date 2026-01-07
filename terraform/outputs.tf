output "repository_url" {
  description = "The URL of the ECR Repository"
  value       = aws_ecr_repository.my_repository.repository_url
}

output "aws_region" {
  description = "The AWS region where resources are deployed"
  value       = var.aws_region
}

output "model_count" {
  description = "The number of models to run in parallel"
  value       = var.model_count
}

output "s3_bucket_name" {
  description = "The name of the S3 bucket used for model files"
  value       =  aws_s3_bucket.model_bucket.bucket
}

output "batch_manager_job_queue_name" {
  description = "The name of the AWS Batch job queue for the manager"
  value       = aws_batch_job_queue.pestpp_manager_queue.name
}

output "batch_worker_job_queue_name" {
  description = "The name of the AWS Batch job queue for workers"
  value       = aws_batch_job_queue.pestpp_worker_queue.name
}

output "batch_manager_job_definition_name" {
  description = "The name of the AWS Batch job definition for the manager"
  value       = aws_batch_job_definition.pestpp_manager.name
}

output "batch_worker_job_definition_name" {
  description = "The name of the AWS Batch job definition for workers"
  value       = aws_batch_job_definition.pestpp_worker.name
}