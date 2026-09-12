#!/bin/sh
set -e

awslocal s3 mb s3://video2frames

create_queue_with_dlq() {
  queue_name=$1
  max_receive_count=$2

  dlq_url=$(awslocal sqs create-queue --queue-name "${queue_name}-dlq" --query QueueUrl --output text)
  dlq_arn=$(awslocal sqs get-queue-attributes --queue-url "$dlq_url" --attribute-names QueueArn --query Attributes.QueueArn --output text)

  attrs_file="/tmp/redrive-${queue_name}.json"
  cat > "$attrs_file" <<EOF
{"RedrivePolicy": "{\"deadLetterTargetArn\":\"${dlq_arn}\",\"maxReceiveCount\":\"${max_receive_count}\"}"}
EOF

  awslocal sqs create-queue --queue-name "$queue_name" --attributes "file://${attrs_file}"

  echo "Fila ${queue_name} criada com DLQ ${queue_name}-dlq (maxReceiveCount=${max_receive_count})"
}

create_queue_with_dlq video-uploaded 3
create_queue_with_dlq video-processed 3
create_queue_with_dlq video-failed 3
create_queue_with_dlq video-processed-notif 3
create_queue_with_dlq video-failed-notif 3

echo "Bucket e filas (com DLQ) do video2frames criados no LocalStack."
