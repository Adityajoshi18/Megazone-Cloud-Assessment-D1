############################################
# S3 DATA LAKE BUCKET
############################################

# Primary data lake bucket for raw and processed clickstream events.
resource "aws_s3_bucket" "data_lake" {
  bucket = var.s3_bucket_name

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

# Enable S3 versioning for resiliency against accidental overwrites or deletions.
resource "aws_s3_bucket_versioning" "data_lake_versioning" {
  bucket = aws_s3_bucket.data_lake.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Configure default server-side encryption for the data lake bucket.
resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake_sse" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block all forms of public access to the data lake bucket.
resource "aws_s3_bucket_public_access_block" "data_lake_block_public_access" {
  bucket = aws_s3_bucket.data_lake.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

############################################
# FIREHOSE ROLE AND DELIVERY STREAM
############################################

# IAM role assumed by Kinesis Data Firehose to access S3 and CloudWatch Logs.
resource "aws_iam_role" "firehose_role" {
  name = "${var.project_name}-${var.environment}-firehose-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "firehose.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Inline policy granting Firehose permission to write to the data lake bucket and log to CloudWatch.
resource "aws_iam_role_policy" "firehose_to_s3_policy" {
  name = "${var.project_name}-${var.environment}-firehose-policy"
  role = aws_iam_role.firehose_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ],
        Resource = [
          aws_s3_bucket.data_lake.arn,
          "${aws_s3_bucket.data_lake.arn}/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}

# Firehose delivery stream that writes raw clickstream events into S3 with date-based partitioning.
resource "aws_kinesis_firehose_delivery_stream" "clickstream_raw_to_s3" {
  name        = var.firehose_stream_name
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose_role.arn
    bucket_arn = aws_s3_bucket.data_lake.arn

    buffering_size     = 5
    buffering_interval = 60

    compression_format  = "GZIP"
    prefix              = "raw/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "raw_failed/!{firehose:error-output-type}/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

############################################
# LAMBDA ROLE AND FUNCTION (RAW -> PROCESSED)
############################################

# IAM role assumed by the Lambda function that transforms raw clickstream data.
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-${var.environment}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Inline policy granting Lambda access to read/write S3 objects and write CloudWatch logs.
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-${var.environment}-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ],
        Resource = [
          aws_s3_bucket.data_lake.arn,
          "${aws_s3_bucket.data_lake.arn}/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Lambda function that processes raw Firehose output and writes transformed events back to S3.
resource "aws_lambda_function" "raw_to_processed" {
  function_name = var.lambda_function_name
  role          = aws_iam_role.lambda_role.arn
  handler       = "processor.lambda_handler"
  runtime       = "python3.12"

  filename         = "../lambda/processor.zip"
  source_code_hash = filebase64sha256("../lambda/processor.zip")

  timeout     = 60
  memory_size = 256

  depends_on = [
    aws_iam_role_policy.lambda_policy
  ]

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

# Permission allowing S3 to invoke the Lambda function.
resource "aws_lambda_permission" "allow_s3_invoke" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.raw_to_processed.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.data_lake.arn
}

# S3 bucket notification to trigger Lambda on new raw GZIP objects.
resource "aws_s3_bucket_notification" "data_lake_notifications" {
  bucket = aws_s3_bucket.data_lake.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.raw_to_processed.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "raw/"
    filter_suffix       = ".gz"
  }

  depends_on = [
    aws_lambda_permission.allow_s3_invoke
  ]
}

############################################
# GLUE DATA CATALOG (DATABASE AND TABLE)
############################################

# Glue database used by Athena for clickstream analytics.
resource "aws_glue_catalog_database" "clickstream_db" {
  name = var.glue_database_name
}

# Glue external table describing processed clickstream events stored in S3.
resource "aws_glue_catalog_table" "clickstream_events" {
  name          = var.glue_table_name
  database_name = aws_glue_catalog_database.clickstream_db.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    classification      = "json"
    "projection.enabled" = "false"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.data_lake.bucket}/processed/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.IgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "json-serde"
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }

    columns {
      name = "event_id"
      type = "string"
    }

    columns {
      name = "page_url"
      type = "string"
    }

    columns {
      name = "event_type"
      type = "string"
    }

    columns {
      name = "event_ts"
      type = "string"
    }

    columns {
      name = "processed_ts"
      type = "string"
    }
  }

  partition_keys {
    name = "year"
    type = "string"
  }

  partition_keys {
    name = "month"
    type = "string"
  }

  partition_keys {
    name = "day"
    type = "string"
  }
}
