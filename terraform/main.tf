# module "pestpp" {
#   source = "./modules/pestpp_aws"
  
#   # AWS Credentials
#   aws_region = "us-east-2"

#   # Compute Environment
#   worker_compute_type = "EC2"  # Use "SPOT" or "EC2" (for on-demand)

#   # Pestpp Agent Variables
#   model_count = 3 # number of agent containers (models to run in parallel)

#   # Environment Variables
#   pestpp_binary       = "pestpp-swp"
#   pestpp_control_file = "sagehen_mf6.pst"
#   model_mount_path    = "/pestpp/model" # where the model resides in the container
#   model_directory     = "model"
#   s3_bucket_name      = "model-output-geomega-1337"
# }