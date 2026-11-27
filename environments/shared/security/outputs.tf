output "guardduty_detector_id" {
  value = aws_guardduty_detector.this.id
}

output "alerts_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "config_bucket" {
  value = aws_s3_bucket.config.bucket
}
