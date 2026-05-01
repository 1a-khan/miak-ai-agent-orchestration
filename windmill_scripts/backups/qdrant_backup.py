# requirements:
# boto3
# requests

import requests
import boto3
import io
from datetime import datetime, timezone


def main(
    qdrant_url: str = "http://localhost:6333",
    company_name: str = "dev",
    aws_access_key_id: str = "$var:u/ammad/AWS_ACCESS_KEY_ID",
    aws_secret_access_key: str = "$var:u/ammad/AWS_SECRET_ACCESS_KEY",
    aws_region: str = "$var:u/ammad/AWS_REGION",
    s3_bucket: str = "$var:u/ammad/AWS_S3_BUCKET",
    s3_prefix: str = "backups/qdrant",
) -> dict:
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")

    s3 = boto3.client(
        "s3",
        aws_access_key_id=aws_access_key_id,
        aws_secret_access_key=aws_secret_access_key,
        region_name=aws_region,
    )

    # --- Get all collections ---
    resp = requests.get(f"{qdrant_url}/collections", timeout=30)
    resp.raise_for_status()
    collections = [c["name"] for c in resp.json().get("result", {}).get("collections", [])]

    if not collections:
        return {"status": "ok", "message": "No collections yet", "company": company_name}

    uploaded = []

    for collection in collections:
        # Create snapshot
        snap_resp = requests.post(
            f"{qdrant_url}/collections/{collection}/snapshots",
            timeout=120,
        )
        snap_resp.raise_for_status()
        snap_name = snap_resp.json()["result"]["name"]

        # Download snapshot into memory
        dl_resp = requests.get(
            f"{qdrant_url}/collections/{collection}/snapshots/{snap_name}",
            stream=True,
            timeout=120,
        )
        dl_resp.raise_for_status()

        buf = io.BytesIO()
        for chunk in dl_resp.iter_content(chunk_size=8192):
            buf.write(chunk)
        size_kb = round(buf.tell() / 1024, 2)
        buf.seek(0)

        # Upload to S3
        s3_key = f"{s3_prefix}/{company_name}/{collection}/{timestamp}_{snap_name}"
        s3.upload_fileobj(buf, s3_bucket, s3_key)

        # Clean up snapshot from Qdrant
        requests.delete(
            f"{qdrant_url}/collections/{collection}/snapshots/{snap_name}",
            timeout=30,
        )

        uploaded.append({"collection": collection, "s3_key": s3_key, "size_kb": size_kb})

    return {
        "status":      "ok",
        "company":     company_name,
        "timestamp":   timestamp,
        "collections": uploaded,
    }
