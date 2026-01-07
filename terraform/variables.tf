#-----------------
#---PEST CONFIG---
#-----------------

variable "model_count" {
  description = "Number of batch worker tasks to run (pestpp agents)"               
  type        = number
  default     = 3
}

#-----------------
#----AWS CONFIG---
#-----------------

variable "aws_region" {
  description = "AWS region for the infrastructure"
  type        = string
  default     = "us-east-2"
}

variable "availability_zones" {
  description = "List of availability zones to use"
  type        = list(string)
  default     = ["us-east-2a", "us-east-2b", "us-east-2c"]
}

variable "default_tags" {
  type = map(string)
  default = {
    Environment = "pestpp-dev"
    Team        = "geomega-hydrogeology"
    Application     = "PEST++"
    Owner       = "john.doe"
  }
}

variable "worker_compute_type" {
  description = "Type of compute environment for worker instances (SPOT or EC2)"
  type        = string
  default     = "SPOT"
  validation {
    condition     = contains(["SPOT", "EC2"], var.worker_compute_type)
    error_message = "Worker compute type must be either 'SPOT' or 'EC2' (on-demand)."
  }
}