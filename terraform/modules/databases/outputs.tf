output "ngo_db_endpoint" {
  value = aws_db_instance.postgres["ngo"].endpoint
}

output "ngo_db_address" {
  value = aws_db_instance.postgres["ngo"].address
}

output "ngo_db_name" {
  value = aws_db_instance.postgres["ngo"].db_name
}

output "donation_db_endpoint" {
  value = aws_db_instance.postgres["donation"].endpoint
}

output "donation_db_address" {
  value = aws_db_instance.postgres["donation"].address
}

output "donation_db_name" {
  value = aws_db_instance.postgres["donation"].db_name
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.volunteers.name
}

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.volunteers.arn
}

output "dynamodb_stream_arn" {
  value = aws_dynamodb_table.volunteers.stream_arn
}
