#!/bin/bash
# SSM 파라미터 값 복구 스크립트
# terraform apply 후에 실행합니다.
#
# 사용법:
#   bash scripts/ssm-restore.sh
#
# 전제 조건: scripts/ssm-backup.json 파일이 있어야 합니다.

set -euo pipefail

REGION="ap-northeast-2"
BACKUP="scripts/ssm-backup.json"

if [ ! -f "${BACKUP}" ]; then
  echo "오류: ${BACKUP} 파일이 없습니다. ssm-backup.sh를 먼저 실행하세요."
  exit 1
fi

COUNT=$(jq.exe 'length' "${BACKUP}" | tr -d '\r')
echo "SSM 파라미터 복구 중... (${COUNT}개)"

jq.exe -c '.[]' "${BACKUP}" | tr -d '\r' | while read -r param; do

  NAME=$(echo "${param}" | jq.exe -r '.Name' | tr -d '\r')
  VALUE=$(echo "${param}" | jq.exe -r '.Value' | tr -d '\r')
  TYPE=$(echo "${param}" | jq.exe -r '.Type' | tr -d '\r')

  # CHANGE_ME는 아직 채우지 않은 값이므로 건너뜁니다.
  if [ "${VALUE}" = "CHANGE_ME" ]; then
    echo "  건너뜀 (미입력): ${NAME}"
    continue
  fi

  # kafka/private-ip는 terraform apply가 새 EC2 IP로 자동 채움.
  # 백업된 옛날 IP로 덮어쓰면 Kafka 광고 주소와 Prometheus 타겟이 틀어짐.
  if [[ "${NAME}" == */kafka/private-ip ]]; then
    echo "  건너뜀 (terraform 자동 관리): ${NAME}"
    continue
  fi

  aws.exe ssm put-parameter \
    --name "${NAME}" \
    --value "${VALUE}" \
    --type "${TYPE}" \
    --overwrite \
    --region "${REGION}" > /dev/null

  echo "  복구 완료: ${NAME}"
done

echo "완료."
