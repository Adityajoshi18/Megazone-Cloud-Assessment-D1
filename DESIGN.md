# Design Document – Serverless Clickstream Data Pipeline (ETL/ELT)

## 1. Overview

This document describes the architecture, design decisions, data flow, and trade-offs for the Serverless Clickstream Data Pipeline built for Assignment D1.

The goal of the pipeline is to ingest high-volume JSON clickstream events, store them in an S3 data lake, transform them, catalog them for analytical use, and make them queryable through Amazon Athena. This is to be done using serverless AWS services and fully managed via Infrastructure as Code (Terraform).

## 2. Architecture Summary

The pipeline consists of the following components:

- **Kinesis Data Firehose** for streaming ingestion.
- **Amazon S3 (Raw Zone)** for storing batched, GZIP-compressed JSON data from Firehose.
- **AWS Lambda** for event-driven transformation (JSON → enriched JSON).
- **Amazon S3 (Processed Zone)** for storing cleaned and enriched data.
- **AWS Glue Data Catalog** for defining schema and partitions.
- **Amazon Athena** for interactive SQL queries over processed data.
- **Terraform** for declarative provisioning of all cloud resources.

## 3. Detailed Data Flow

### Step 1 — Event Ingestion

A producer sends JSON-formatted clickstream events using Firehose's `PutRecord` API.

Firehose buffers and delivers data to S3 in:
- GZIP format
- Partitioned by date (based on ingestion timestamp)

Example raw path:

`s3://<bucket>/raw/year=2025/month=11/day=26/file.gz`

### Step 2 — Raw Data Landing in S3

When Firehose writes a new object to the `raw/` prefix, S3 generates an `ObjectCreated` event.
A notification triggers the Lambda transformation function.

Key properties:

- Triggered only for `.gz` files
- Trigger restricted to `raw/` prefix to reduce unnecessary Lambda invocations

### Step 3 — Lambda Transformation Logic

Lambda performs:

1. **Download raw GZIP file** from S3.
2. **Decompress** newline-delimited JSON.
3. **Process each event**:
    - Remove `user_id` (PII removal).
    - Add `processed_ts` (server-side timestamp).
4. **Write transformed JSON** to: `processed/year=2025/month=11/day=26/file.json`

Benefits:
- Data is clean and analytics-ready.
- Schema remains flat and predictable.
- Partitioning is inherited from the raw structure.

### Step 4 — Glue Data Catalog

Due to restricted AWS account permissions, **Glue Crawlers could not be created**  
(AWS responded with `AccessDeniedException`).

To meet assignment requirements:

- A **Glue database** and **external table** are created *directly via Terraform*.
- The schema matches the Lambda output structure.
- Partition keys: `year`, `month`, `day`
- The table references: `s3://<bucket>/processed/`

Partitions are loaded manually in Athena:

```sql
MSCK REPAIR TABLE clickstream_events;
```

This approach satisfies the requirement to organize and catalog processed data despite account limitations.

### Step 5 — Querying in Athena

Users can query processed data using standard SQL.

```sql
SELECT event_type, COUNT(*)
FROM clickstream_db.clickstream_events
WHERE year='2025' AND month='11' AND day='26'
GROUP BY event_type;
```

Athena reads JSON files directly from S3 using the Glue table schema.

Queries benefit from:
- Partition pruning
- Column projection
- Serverless architecture (no cluster management)

## 4. Infrastructure as Code (Terraform)

Terraform provisions the entire pipeline:

**S3**
- Bucket for raw + processed zones
- Versioning
- Encryption (AES256)
- Public access blocking
- S3 → Lambda event notifications

**Firehose**
- IAM role for S3 + CloudWatch
- Delivery stream with:
    - GZIP compression
    - Date-based prefixing
    - Error output location

**Lambda**
- IAM execution role
- S3 trigger permissions

**Glue Catalog**
- Database
- External table describing processed JSON schema
- Partition metadata

**Athena**
- Users set an output location manually in UI
- Queries execute immediately after partition repair

## 5. Design Justification & Trade-offs

**5.1 Serverless Architecture**

All components are serverless:
- No servers to manage
- Auto-scaling
- Pay-per-use model
- Minimal operational overhead

**5.2 Why Firehose Instead of Kinesis Streams**

Firehose:
- Automatically batches and writes to S3
- Requires no consumer or worker infrastructure
- Built-in retry and error handling
- Lower operational load

For this assignment, Firehose provided the simplest ingestion path.

**5.3 Why Lambda Instead of AWS Glue ETL Job**

Intended plan: use Glue ETL job or Glue Crawler.

Blocked by:
`AccessDeniedException: Account <id> is denied access to create Glue Crawler`

Therefore:
- Lambda used as transformation engine
- Glue table defined via Terraform

This still fulfills:
- Transformation requirement
- Cataloging requirement
- Querying requirement

**5.4 JSON vs Parquet**

JSON chosen because:
- Easy for demonstration
- No extra serialization frameworks
- Glue JSON SerDe is built-in

For production:
- Converting processed output to Parquet would reduce scan cost.
- This could be done via a second Lambda or Glue ETL job. 

## 6. Security Considerations

- IAM roles follow least-privilege principles.
- S3 bucket fully blocks public access.
- Server-side encryption enabled (AES256).
- Lambda only has permission to access specific bucket paths.

No credentials or account IDs are hardcoded.

## 7. Cost Considerations

Minimal cost components:
- Firehose ingestion (GB-based for actual data)
- S3 storage (cents for small files)
- Lambda (invoked only when raw files land)
- Glue catalog (very low cost)
- Athena (charged per scanned data; small for JSON)

This pipeline is extremely cost-efficient for development workloads.

## 8. Future Enhancements

Potential improvements:

**Data Optimization**

- Convert processed JSON → Parquet for better Athena performance.
- Add S3 lifecycle policies for archival.

**Observability**

- CloudWatch dashboards for Firehose delivery failures.
- Lambda error alarms (using CloudWatch Alarms or EventBridge).

**Scalability**

- Parallel Lambda processing via concurrency controls.
- Multi-prefix Firehose setup for different event types.

**Data Governance**

- Integration with AWS Lake Formation.
- Automated schema evolution.

## 9. Conclusion

This pipeline implements a complete, serverless ETL/ELT workflow suitable for real-time clickstream analytics.
It is reproducible (Terraform), scalable (serverless), observable (CloudWatch), and queryable (Athena), while aligning with the assignment requirements even under AWS account limitations.

The result is a clean, production-quality architecture designed from first principles and implemented end-to-end.














