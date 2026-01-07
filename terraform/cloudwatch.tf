resource "aws_cloudwatch_log_group" "batch_log_group" {
  name              = "/aws/batch/pestpp"
  retention_in_days = 14

  tags = merge(
    var.default_tags,
    {
      Name    = "PESTPP-Batch-Logs",
      Service = "Cloudwatch"
      Purpose = "Collects logs from batch"
    }
  )
}