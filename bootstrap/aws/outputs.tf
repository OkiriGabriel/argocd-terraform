output "bucket_name" {
  description = "Use as `bucket` in dev/backend.hcl and prod/backend.hcl."
  value       = aws_s3_bucket.state.id
}

output "kms_key_arn" {
  description = "KMS key encrypting state objects."
  value       = aws_kms_key.state.arn
}
