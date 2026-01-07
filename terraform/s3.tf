resource "random_string" "bucket_suffix" {
  length  = 7
  lower   = true
  upper   = false
  numeric = true
  special = false
}

resource "aws_s3_bucket" "model_bucket" {
  bucket = "pestpp-s3-bucket-${random_string.bucket_suffix.result}"

  force_destroy = true

  tags = merge(
    var.default_tags,
    {
      Service = "File Storage",
      Purpose = "Stores model output files"
    }
  )
}

resource "aws_s3_object" "pestpp_model_files" {
  for_each = fileset("../model", "**/*")  # Loop through files and folders in a local directory

  bucket = aws_s3_bucket.model_bucket.bucket
  key    = "model/${each.key}"
  source = "../model/${each.key}"  # Local file path
  acl    = "private"
}