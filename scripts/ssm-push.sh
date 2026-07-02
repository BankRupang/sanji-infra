#!/bin/bash
# SSM 파라미터 값 복구 스크립트
# terraform apply 후에 실행합니다.
#
# 사용법:
#   bash scripts/ssm-push.sh
#
# 전제 조건: scripts/ssm-backup.json 파일이 있어야 합니다.

set -uo pipefail

REGION="ap-northeast-2"
BACKUP="scripts/ssm-backup.json"

if [ ! -f "${BACKUP}" ]; then
  echo "오류: ${BACKUP} 파일이 없습니다. ssm-backup.sh를 먼저 실행하세요."
  exit 1
fi

COUNT=$(jq.exe 'length' "${BACKUP}" | tr -d '\r')
echo "SSM 파라미터 복구 중... (${COUNT}개)"

ok=0
skip=0
fail=0

# 파이프를 while에 직접 연결하면 서브쉘에서 실행되어 오류 시 루프 전체가 조용히 멈춥니다.
# 임시 파일로 분리해서 while 루프가 현재 쉘에서 실행되도록 합니다.
tmpfile=$(mktemp)
jq.exe -c '.[]' "${BACKUP}" | tr -d '\r' > "${tmpfile}"

while IFS= read -r param; do

  NAME=$(echo "${param}" | jq.exe -r '.Name' | tr -d '\r')
  VALUE=$(echo "${param}" | jq.exe -r '.Value' | tr -d '\r')
  TYPE=$(echo "${param}" | jq.exe -r '.Type' | tr -d '\r')

  # CHANGE_ME는 아직 채우지 않은 값이므로 건너뜁니다.
  if [ "${VALUE}" = "CHANGE_ME" ]; then
    echo "  건너뜀 (미입력): ${NAME}"
    skip=$((skip + 1))
    continue
  fi

  # kafka/private-ip는 terraform apply가 새 EC2 IP로 자동 채움.
  # 백업된 옛날 IP로 덮어쓰면 Kafka 광고 주소와 Prometheus 타겟이 틀어짐.
  if [[ "${NAME}" == */kafka/private-ip ]]; then
    echo "  건너뜀 (terraform 자동 관리): ${NAME}"
    skip=$((skip + 1))
    continue
  fi

  if aws.exe ssm put-parameter \
    --name "${NAME}" \
    --value "${VALUE}" \
    --type "${TYPE}" \
    --overwrite \
    --region "${REGION}" > /dev/null < /dev/null; then
    echo "  복구 완료: ${NAME}"
    ok=$((ok + 1))
  else
    echo "  실패: ${NAME}"
    fail=$((fail + 1))
  fi

done < "${tmpfile}"

rm -f "${tmpfile}"

echo ""
echo "완료: 복구 ${ok}개, 건너뜀 ${skip}개, 실패 ${fail}개"

if [ "${fail}" -gt 0 ]; then
  exit 1
fi
