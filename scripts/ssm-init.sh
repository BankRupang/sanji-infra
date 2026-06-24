#!/bin/bash
# SSM 파라미터 초기화 JSON 템플릿 생성
# bootstrap apply 후 AWS에서 파라미터 목록을 읽어 JSON 템플릿을 만듭니다.
#
# 사용법:
#   bash scripts/ssm-init.sh
#   # 생성된 scripts/ssm-backup.json을 열어 CHANGE_ME를 실제 값으로 교체
#   bash scripts/ssm-restore.sh
#
# 주의: 값을 채운 ssm-backup.json은 시크릿이 포함되므로 git에 올리지 마세요.

set -euo pipefail

REGION="ap-northeast-2"
PREFIX="/sanji/prod"
OUTPUT="scripts/ssm-backup.json"

echo "SSM 파라미터 목록 조회 중... (경로: ${PREFIX})"

aws.exe ssm get-parameters-by-path \
  --path "${PREFIX}" \
  --recursive \
  --region "${REGION}" \
  --query "Parameters[*].Name" \
  --output json \
  | tr -d '\r' \
  | jq.exe '[.[] | {Name: ., Value: "CHANGE_ME", Type: "SecureString"}]' > "${OUTPUT}"

COUNT=$(jq.exe 'length' "${OUTPUT}" | tr -d '\r')
echo "생성 완료: ${COUNT}개 파라미터 → ${OUTPUT}"
echo "CHANGE_ME를 실제 값으로 교체한 뒤 bash scripts/ssm-restore.sh 를 실행하세요."
echo "CHANGE_ME로 남겨둔 항목은 ssm-restore.sh가 건너뜁니다."
