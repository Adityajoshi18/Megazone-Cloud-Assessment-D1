# Global configuration variables for this deployment.

variable "aws_region" {
  description = "AWS region to deploy resources into"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Optional AWS CLI profile name"
  type        = string
  default     = ""
}

variable "project_name" {
  description = "Short name for this project, used in resource naming"
  type        = string
  default     = "clickstream-pipeline"
}

variable "environment" {
  description = "Deployment environment (e.g., dev, prod)"
  type        = string
  default     = "dev"
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket to store raw and processed data (must be globally unique)"
  type        = string
}

variable "firehose_stream_name" {
  description = "Name of the Kinesis Data Firehose delivery stream"
  type        = string
  default     = "clickstream-firehose-dev"
}

variable "lambda_function_name" {
  description = "Name of the Lambda function that processes raw clickstream files"
  type        = string
  default     = "clickstream-raw-to-processed-dev"
}

variable "glue_database_name" {
  description = "Glue Data Catalog database name for clickstream data"
  type        = string
  default     = "clickstream_db"
}

variable "glue_table_name" {
  description = "Glue Data Catalog table name for processed clickstream events"
  type        = string
  default     = "clickstream_events"
}
