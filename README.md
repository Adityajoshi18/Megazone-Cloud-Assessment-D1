# Serverless Clickstream Data Pipeline (ETL/ELT)

This repository contains a fully serverless data pipeline built on AWS for ingesting, transforming, and querying JSON clickstream events.
It was developed as part of **Assignment D1: Serverless Data Processing Pipeline (ETL/ELT)**.

The pipeline uses:
- **Kinesis Data Firehose** – streaming ingestion
- **Amazon S3** – raw + processed data lake
- **AWS Lambda** – transformation (JSON → enriched JSON)
- **AWS Glue Data Catalog** – schema for Athena
- **Amazon Athena** – interactive SQL queries
- **Terraform** – full Infrastructure as Code (IaC)

The implementation is fully automated end-to-end.

High-level flow:

```text
┌──────────────────┐
│  Clickstream App │
└───────┬──────────┘
        │  PutRecord (JSON)
        ▼
┌────────────────────────────┐
│  Kinesis Data Firehose     │
└───────────┬───────────────┘
        │  batched, gzipped
        ▼
┌────────────────────────────────────┐
│     S3 Data Lake (raw zone)       │
│ raw/year=YYYY/month=MM/day=DD/    │
└───────────────┬───────────────────┘
            │ S3 ObjectCreated event
            ▼
┌──────────────────────────┐
│   AWS Lambda Processor   │
└───────────┬──────────────┘
            │ transformed JSON
            ▼
┌────────────────────────────────────────┐
│      S3 Data Lake (processed zone)     │
│ processed/year=YYYY/month=MM/day=DD/   │
└───────────────────┬────────────────────┘
            │ Glue catalog table
            ▼
┌────────────────────────┐
│      Amazon Athena     │
└────────────────────────┘
```

## Repository Structure

```bash
data-engineering/
├── lambda/
│   ├── processor.py        
│   └── processor.zip  #Ignored by git     
└── terraform/
    ├── main.tf             
    ├── variables.tf        
    ├── versions.tf         
    ├── outputs.tf          
    ├── terraform.tfvars    
    └── terraform.lock.hcl 
├── sample-event.json          
README.md                   
DESIGN.md                   
.gitignore                          
```

## Getting Started

1. Prerequisites

### Install AWS CLI

Verify:

```bash
aws --version
```

### Configure AWS credentials

If you haven’t configured AWS before:

```bash
aws configure
```

Enter:
- AWS Access Key ID
- AWS Secret Access Key
- Region (e.g., `us-east-1`)
- Output format (optional)

Verify credentials:

```bash
aws sts get-caller-identity
```

2. Install Terraform

Verify:

```bash
terraform -version
```

3. Update terraform.tfvars

Open:

```bash
data-engineering/terraform/terraform.tfvars
```

Replace bucket name placeholder:

```bash
s3_bucket_name = "your-unique-bucket-name"
```

The bucket name must be globally unique.

4. Package the Lambda Function

From inside `data-engineering/lambda/`:

```bash
cd data-engineering/lambda
zip processor.zip processor.py
```

Terraform will deploy this zip.

5. Deploy Infrastructure with Terraform

Go to the Terraform directory:

```bash
cd data-engineering/terraform
terraform init
terraform plan
terraform apply
```

When prompted:

`Enter a value: yes`

Resources created:
- S3 bucket
- Firehose delivery stream
- Lambda function + IAM roles
- S3 → Lambda trigger
- Glue database + table

## Sending Test Ingestion Events

From the repo root:

```bash
cd data-engineering
```

Send an example JSON event through Firehose:

```bash
aws firehose put-record \
  --delivery-stream-name clickstream-firehose-dev \
  --record "{\"Data\": \"$(base64 < sample-event.json)\"}"
```

Firehose writes:

`s3://<bucket>/raw/year=YYYY/month=MM/day=DD/...`

Lambda automatically transforms and writes:

`s3://<bucket>/processed/year=YYYY/month=MM/day=DD/...json`

Verify:

```bash
aws s3 ls s3://your-bucket/raw/
aws s3 ls s3://your-bucket/processed/
```

## Querying in Athena

1. Open Athena → Query Editor

Set query result location (once):

`s3://your-bucket/athena-results/`

2. Load partitions

```sql
MSCK REPAIR TABLE clickstream_events;
```

3. Sample queries

Get 10 events:

```sql
SELECT *
FROM clickstream_db.clickstream_events
LIMIT 10;
```

Filter by partition:

```sql
SELECT *
FROM clickstream_db.clickstream_events
WHERE year='2025' AND month='11' AND day='26'
LIMIT 10;
```

Count events:

```sql
SELECT event_type, COUNT(*)
FROM clickstream_db.clickstream_events
GROUP BY event_type;
```

## Cleanup (Avoid Unnecessary AWS Charges)

```bash
cd data-engineering/terraform
terraform destroy
```

## Technologies Used

- AWS Kinesis Data Firehose
- AWS S3
- AWS Lambda
- AWS Glue Catalog
- Amazon Athena
- Terraform

## Notes About Glue Crawler Requirement

The original assignment suggests using AWS Glue Crawler.
However, this AWS account returns:

`AccessDeniedException: Account <id> is denied access to Glue Crawler`

Because of this platform limitation, the Glue Catalog table is created directly via Terraform, which still provides:
- schema inference
- Athena querying
- partition awareness

This satisfies the functional requirement while acknowledging account restrictions.

## Summary

This repository demonstrates:
- Serverless pipeline design
- Streaming ingestion
- Automated S3-based ETL
- Partitioned data lakes
- Cataloging without Glue crawlers
- SQL analytics with Athena
- Completely IaC-managed deployment

It can be deployed by anyone with an AWS account and Terraform installed.









