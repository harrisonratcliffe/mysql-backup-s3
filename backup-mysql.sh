#!/bin/bash

# Database Configuration
DB_USER="mysqluser"
DB_PASSWORD="mysqlpass"
DB_NAME="dbname"
DB_HOST="localhost"

# S3 Configuration
BUCKET_NAME="bucketname"
S3_ENDPOINT="https://s3.storage.endpoint.com"
LOCAL_BACKUP_DIR="/tmp/mysql-backups"
S3_BACKUP_DIR="backups"
DATE=$(date +"%Y%m%d%H%M")
BACKUP_FILE="$LOCAL_BACKUP_DIR/${DB_NAME}_backup_$DATE.sql.gz"

# Optional Features
DELETE_LOCAL_BACKUP="true"
SEND_HEARTBEAT="false"
HEARTBEAT_URL="https://hc.hyperping.io/tok_DOKTgKwaHzPVyxbUzjBE3LkW"
BACKUP_RETENTION_DAYS=30



# Create local backup directory if it doesn't exist
mkdir -p $LOCAL_BACKUP_DIR

# Create MySQL backup
mysqldump -u $DB_USER -p"$DB_PASSWORD" -h $DB_HOST $DB_NAME | gzip > "$BACKUP_FILE"

# Check if the backup was successful
if [[ $? -ne 0 ]]; then
    echo "MySQL backup failed"
    exit 1
else
    echo "MySQL backup created: $BACKUP_FILE"
fi

# Upload to Cloudflare S3 using s3api put-object, with folder prefix defined
aws s3api put-object --bucket "$BUCKET_NAME" --key "$S3_BACKUP_DIR/$(basename "$BACKUP_FILE")" --body "$BACKUP_FILE" --endpoint-url "$S3_ENDPOINT" --checksum-algorithm CRC32

# Check if the upload was successful
if [[ $? -ne 0 ]]; then
    echo "Upload to S3 Storage failed"
    exit 1
else
    echo "Upload to S3 Storage successful"

    # Delete local backup after successful upload if option is enabled
    if [[ "$DELETE_LOCAL_BACKUP" == "true" ]]; then
        rm "$BACKUP_FILE"
        echo "Local backup deleted: $BACKUP_FILE"
    fi

    # Send HTTP request to heartbeat monitor if option is enabled
    if [[ "$SEND_HEARTBEAT" == "true" ]]; then
        curl -X GET "$HEARTBEAT_URL" >/dev/null 2>&1
        if [[ $? -ne 0 ]]; then
            echo "Failed to send heartbeat request"
        else
            echo "Heartbeat sent successfully"
        fi
    fi
fi

# Delete old backups older than BACKUP_RETENTION_DAYS
if [[ $BACKUP_RETENTION_DAYS -gt 0 ]]; then
    find "$LOCAL_BACKUP_DIR" -type f -name "${DB_NAME}_backup_*.sql.gz" -mtime +$BACKUP_RETENTION_DAYS -exec rm {} \;
    echo "Old backups older than $BACKUP_RETENTION_DAYS days deleted successfully"
else
    echo "Backup deletion is disabled (BACKUP_RETENTION_DAYS is set to 0)"
fi
