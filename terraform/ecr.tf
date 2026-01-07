resource "aws_ecr_repository" "my_repository" {
  name                 = "pestpp"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }

  force_delete = true

  tags = merge(
    var.default_tags,
    {
      Service = "ECR Repository",
      Purpose = "Stores docker containers to be deployed to EC2 instances"
    }
  )
}
