#!/bin/bash
BUCKET="cv-23l-3026"
export AWS_DEFAULT_REGION="ap-southeast-2"
STAGE="/opt/cv-stage"
WEB="/var/www/html"
LOG="/var/log/cv-sync.log"

TOKEN=$(curl -s --max-time 5 -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
IID=$(curl -s --max-time 5 -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)

mkdir -p "$STAGE"
if aws s3 sync "s3://$BUCKET/site/" "$STAGE" --delete --quiet \
   && [ -n "$IID" ] \
   && cp "$STAGE/style.css" "$STAGE/cv.pdf" "$WEB/" \
   && sed "s/{{HOSTED_ON}}/EC2 $IID/" "$STAGE/index.html" > "$WEB/index.html" \
   && chmod 644 "$WEB/index.html" "$WEB/style.css" "$WEB/cv.pdf"; then
  echo "$(date -Is) sync OK" >> "$LOG"
else
  echo "$(date -Is) sync FAILED" >> "$LOG"
fi
