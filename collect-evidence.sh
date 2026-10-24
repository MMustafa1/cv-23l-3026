#!/bin/bash
# Usage: ./collect-evidence.sh <bucket> <ec2-address> <lambda-address>
if [ $# -ne 3 ]; then
  echo "Usage: $0 <bucket-name> <ec2-address> <lambda-address>"
  exit 1
fi

BUCKET="$1"
EC2_URL="${2%/}"
LAMBDA_URL="${3%/}"
case "$EC2_URL" in http*) ;; *) EC2_URL="http://$EC2_URL" ;; esac
case "$LAMBDA_URL" in http*) ;; *) LAMBDA_URL="https://$LAMBDA_URL" ;; esac

ROLL="23l-3026"
export AWS_DEFAULT_REGION="ap-southeast-2"
EC2_ROLE="cv-ec2-role-$ROLL"
LAMBDA_ROLE="cv-lambda-role-$ROLL"
FUNC="cv-func-$ROLL"
SG_NAME="cv-sg-$ROLL"
INSTANCE_NAME="cv-ec2-$ROLL"
S3_URL="https://$BUCKET.s3.$AWS_DEFAULT_REGION.amazonaws.com/site/index.html"
OUT="evidence.txt"
: > "$OUT"

hdr() { [ -s "$OUT" ] && echo >> "$OUT"; echo "== $1 ==" >> "$OUT"; }
run() { "$@" >> "$OUT" 2>&1 || echo "FAILED: $*" >> "$OUT"; }

role_inline() {
  local role="$1" names p
  names=$(aws iam list-role-policies --role-name "$role" --query 'PolicyNames[]' --output text) || return 1
  for p in $names; do
    aws iam get-role-policy --role-name "$role" --policy-name "$p" --output json || return 1
  done
}

logs_tail() {
  set -o pipefail
  aws logs tail "/aws/lambda/$FUNC" --since 1d | grep '"fn"' | tail -n 10
}

hdr caller
run aws sts get-caller-identity --output json

hdr public-access
run aws s3api get-public-access-block --bucket "$BUCKET" --output json

hdr versioning
run aws s3api get-bucket-versioning --bucket "$BUCKET" --output json

hdr objects
run aws s3 ls "s3://$BUCKET/" --recursive

hdr ec2-policy
run role_inline "$EC2_ROLE"

hdr lambda-policy
run aws iam list-attached-role-policies --role-name "$LAMBDA_ROLE" --output json
run role_inline "$LAMBDA_ROLE"

hdr security-group
run aws ec2 describe-security-groups --filters "Name=group-name,Values=$SG_NAME" \
  --query 'SecurityGroups[].IpPermissions' --output json

hdr instance
run aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].{InstanceId:InstanceId,Type:InstanceType,IMDS:MetadataOptions.HttpTokens,Profile:IamInstanceProfile.Arn,PublicIp:PublicIpAddress}' \
  --output json

hdr endpoints
for u in "$EC2_URL/" "$EC2_URL/style.css" "$EC2_URL/cv.pdf" \
         "$LAMBDA_URL/" "$LAMBDA_URL/style.css" "$LAMBDA_URL/cv.pdf" "$LAMBDA_URL/anything" \
         "$S3_URL"; do
  printf '%s -> ' "$u" >> "$OUT"
  curl -s -o /dev/null --max-time 15 -w '%{http_code} %{content_type}\n' "$u" >> "$OUT" 2>&1 \
    || echo "FAILED" >> "$OUT"
done

hdr lambda-logs
run logs_tail

hdr log-retention
run aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/$FUNC" \
  --query 'logGroups[].{Name:logGroupName,RetentionDays:retentionInDays}' --output json

echo DONE
