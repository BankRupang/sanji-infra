#!/bin/bash
# SSM 파라미터 값 백업 스크립트
# terraform destroy 전에 실행합니다.
#
# 사용법:
#   bash scripts/ssm-backup.sh
#
# 결과: ssm-backup.json 파일에 현재 SSM 파라미터 값을 저장합니다.
#       이 파일은 git에 올리지 마세요 (시크릿 포함).

set -euo pipefail

REGION="ap-northeast-2"
PREFIX="/sanji/prod"
OUTPUT="scripts/ssm-backup.json"

echo "SSM 파라미터 백업 중... (경로: ${PREFIX})"

aws.exe ssm get-parameters-by-path \
  --path "${PREFIX}" \
  --recursive \
  --with-decryption \
  --region "${REGION}" \
  --query "Parameters[*].{Name:Name,Value:Value,Type:Type}" \
  --output json > "${OUTPUT}"

COUNT=$(jq.exe 'length' "${OUTPUT}" | tr -d '\r')
echo "완료: ${COUNT}개 파라미터를 ${OUTPUT}에 저장했습니다."
echo "주의: 이 파일에 시크릿이 포함되어 있습니다. git에 커밋하지 마세요."
