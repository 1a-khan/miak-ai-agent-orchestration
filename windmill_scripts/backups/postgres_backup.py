# requirements:
# psycopg2-binary
# boto3

import psycopg2
import boto3
import gzip
import io
from datetime import datetime, timezone


def main(
    database_url: str = "postgres://abm:abm@localhost:5433/agentic_business_mapper_dev",
    company_name: str = "dev",
    aws_access_key_id: str = "$var:u/ammad/AWS_ACCESS_KEY_ID",
    aws_secret_access_key: str = "$var:u/ammad/AWS_SECRET_ACCESS_KEY",
    aws_region: str = "$var:u/ammad/AWS_REGION",
    s3_bucket: str = "$var:u/ammad/AWS_S3_BUCKET",
    s3_prefix: str = "backups/postgres",
) -> dict:
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")

    # --- Connect and dump all tables to SQL ---
    conn = psycopg2.connect(database_url)
    conn.autocommit = True
    cur = conn.cursor()

    # Get all tables
    cur.execute("""
        SELECT tablename FROM pg_tables
        WHERE schemaname = 'public'
        AND tablename != 'schema_migrations'
        ORDER BY tablename
    """)
    tables = [row[0] for row in cur.fetchall()]

    sql_lines = [
        f"-- Backup of {company_name} — {timestamp}",
        "SET client_encoding = 'UTF8';",
        "BEGIN;",
        ""
    ]

    for table in tables:
        cur.execute(f"SELECT * FROM {table}")
        rows = cur.fetchall()
        cols = [desc[0] for desc in cur.description]

        sql_lines.append(f"-- Table: {table} ({len(rows)} rows)")

        for row in rows:
            values = []
            for val in row:
                if val is None:
                    values.append("NULL")
                elif isinstance(val, bool):
                    values.append("TRUE" if val else "FALSE")
                elif isinstance(val, (int, float)):
                    values.append(str(val))
                elif isinstance(val, list):
                    escaped = [str(v).replace("'", "''") for v in val]
                    values.append("ARRAY[" + ",".join(f"'{e}'" for e in escaped) + "]")
                elif isinstance(val, dict):
                    import json
                    values.append("'" + json.dumps(val).replace("'", "''") + "'::jsonb")
                else:
                    values.append("'" + str(val).replace("'", "''") + "'")

            col_list = ", ".join(cols)
            val_list = ", ".join(values)
            sql_lines.append(
                f"INSERT INTO {table} ({col_list}) VALUES ({val_list}) ON CONFLICT DO NOTHING;"
            )

        sql_lines.append("")

    sql_lines.append("COMMIT;")
    cur.close()
    conn.close()

    # --- Gzip in memory ---
    sql_bytes = "\n".join(sql_lines).encode("utf-8")
    buf = io.BytesIO()
    with gzip.GzipFile(fileobj=buf, mode="wb") as gz:
        gz.write(sql_bytes)
    buf.seek(0)

    size_kb = round(len(buf.getvalue()) / 1024, 2)

    # --- Upload to S3 ---
    s3_key = f"{s3_prefix}/{company_name}/{timestamp}.sql.gz"
    s3 = boto3.client(
        "s3",
        aws_access_key_id=aws_access_key_id,
        aws_secret_access_key=aws_secret_access_key,
        region_name=aws_region,
    )
    s3.upload_fileobj(buf, s3_bucket, s3_key)

    return {
        "status":    "ok",
        "company":   company_name,
        "s3_key":    s3_key,
        "size_kb":   size_kb,
        "tables":    tables,
        "timestamp": timestamp,
    }
