import base64
import boto3
import uuid
import os
import re
import wmill

# ── Windmill variables used ────────────────────────────────────────────────────
#   u/ammad/AWS_ACCESS_KEY_ID      — AWS access key ID
#   u/ammad/AWS_SECRET_ACCESS_KEY  — AWS secret access key
#   u/ammad/AWS_S3_BUCKET          — S3 bucket name


def main(
    action: str,
    file_base64: str,
    filename: str,
    client_name: str = "unknown",
    theme_title: str = "unclassified",
    category: str = "other",
):
    if action != "upload":
        return {"status": "error", "message": f"Unknown action: {action}"}

    aws_access_key = wmill.get_variable("u/ammad/AWS_ACCESS_KEY_ID")
    aws_secret_key = wmill.get_variable("u/ammad/AWS_SECRET_ACCESS_KEY")
    s3_bucket      = wmill.get_variable("u/ammad/AWS_S3_BUCKET")
    aws_region     = os.environ.get("AWS_DEFAULT_REGION", "eu-west-1")

    file_bytes = base64.b64decode(file_base64)
    size_bytes = len(file_bytes)

    safe_client = _slugify(client_name)
    safe_theme  = _slugify(theme_title)
    safe_cat    = _slugify(category)
    ext         = os.path.splitext(filename)[1].lower() or ".bin"
    stored_name = f"{uuid.uuid4().hex}{ext}"
    s3_key      = f"{safe_client}/{safe_theme}/{safe_cat}/{stored_name}"

    s3 = boto3.client(
        "s3",
        aws_access_key_id=aws_access_key,
        aws_secret_access_key=aws_secret_key,
        region_name=aws_region,
    )

    s3.put_object(
        Bucket=s3_bucket,
        Key=s3_key,
        Body=file_bytes,
        ContentType=_content_type(ext),
    )

    presigned_url = s3.generate_presigned_url(
        "get_object",
        Params={"Bucket": s3_bucket, "Key": s3_key},
        ExpiresIn=604800,  # 7 days
    )

    return {
        "status":            "success",
        "filename":          stored_name,
        "original_filename": filename,
        "s3_key":            s3_key,
        "s3_bucket":         s3_bucket,
        "size_bytes":        size_bytes,
        "presigned_url":     presigned_url,
    }


def _slugify(value: str) -> str:
    value = value.lower().strip()
    value = re.sub(r"[^\w\s-]", "", value)
    value = re.sub(r"[\s_-]+", "-", value)
    return value or "unknown"


def _content_type(ext: str) -> str:
    return {
        ".jpg":  "image/jpeg",
        ".jpeg": "image/jpeg",
        ".png":  "image/png",
        ".gif":  "image/gif",
        ".webp": "image/webp",
        ".pdf":  "application/pdf",
        ".doc":  "application/msword",
        ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        ".xls":  "application/vnd.ms-excel",
        ".xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        ".zip":  "application/zip",
        ".txt":  "text/plain",
    }.get(ext, "application/octet-stream")
