"""
Lambda function to transform raw clickstream data written by Firehose.

This function:
- Is triggered by S3 ObjectCreated events on the raw prefix.
- Downloads GZIP-compressed, newline-delimited JSON from S3.
- Removes selected fields and adds enrichment fields.
- Writes transformed JSON lines back to a processed prefix, preserving partitioning.
"""

import boto3
import gzip
import json
from datetime import datetime, timezone
from io import BytesIO
from urllib.parse import unquote_plus

s3 = boto3.client("s3")


def lambda_handler(event, context):
    """
    Handle S3 ObjectCreated events for raw Firehose output.

    The event can contain multiple records, each corresponding to a new object.
    For each raw object:
    - The body is downloaded and decompressed.
    - Each JSON line is parsed and transformed.
    - Transformed records are written as JSON lines to the processed prefix.
    """
    for record in event.get("Records", []):
        # Bucket and key are taken from the S3 event.
        src_bucket = record["s3"]["bucket"]["name"]
        # Keys in S3 event notifications may be URL-encoded.
        src_key = unquote_plus(record["s3"]["object"]["key"])

        # Retrieve the raw GZIP object from S3.
        raw_obj = s3.get_object(Bucket=src_bucket, Key=src_key)
        raw_body = raw_obj["Body"].read()

        # Decompress the Firehose output, which is stored as GZIP.
        with gzip.GzipFile(fileobj=BytesIO(raw_body), mode="rb") as gz:
            file_content = gz.read().decode("utf-8")

        transformed_lines = []

        # Firehose writes newline-delimited JSON. Process each line independently.
        for line in file_content.splitlines():
            line = line.strip()
            if not line:
                continue

            try:
                event_obj = json.loads(line)
            except json.JSONDecodeError:
                # Skip malformed lines rather than failing the whole batch.
                continue

            # Remove a field that should not be present in the processed output.
            event_obj.pop("user_id", None)

            # Add an enrichment field for traceability and analysis.
            event_obj["processed_ts"] = datetime.now(timezone.utc).isoformat()

            transformed_lines.append(json.dumps(event_obj))

        # If nothing valid was produced, skip writing a processed file.
        if not transformed_lines:
            continue

        transformed_body = "\n".join(transformed_lines).encode("utf-8")

        # Map raw path to processed path while preserving partition structure.
        # Example:
        #   raw/year=2025/month=11/day=26/file.gz
        # becomes:
        #   processed/year=2025/month=11/day=26/file.json
        if src_key.startswith("raw/"):
            rest = src_key[len("raw/"):]
            dest_key = f"processed/{rest}"
        else:
            dest_key = f"processed/{src_key}"

        # Use a .json suffix for readability and to match the Glue/Athena expectations.
        if dest_key.endswith(".gz"):
            dest_key = dest_key[:-3] + "json"

        # Write the transformed payload back to S3.
        s3.put_object(
            Bucket=src_bucket,
            Key=dest_key,
            Body=transformed_body,
            ContentType="application/json",
        )

    return {"status": "ok"}
