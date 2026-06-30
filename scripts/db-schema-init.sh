#!/bin/bash
# Terraform null_resource에서 자동 호출되는 스크립트입니다.
# Flyway가 관리하지 않는 외부 서비스(Keycloak, Langfuse) 스키마를 RDS에 생성합니다.
#
# 필수 환경변수 (null_resource environment 블록에서 주입):
#   REGION       - AWS 리전
#   INSTANCE_ID  - 모니터링 EC2 인스턴스 ID
#   RDS_HOST     - RDS 엔드포인트
#   DB_USER      - DB 마스터 계정
#   DB_NAME      - DB 이름
#   SSM_PW_PATH  - SSM Parameter Store의 DB 비밀번호 경로

set -euo pipefail

# ----------------------------------------
# 1. SSM Agent 준비 대기
# ----------------------------------------
echo "[1/3] SSM Agent 준비 대기 중... (최대 5분)"
for i in $(seq 1 30); do
  STATUS=$(aws ssm describe-instance-information \
    --filters "Key=InstanceIds,Values=${INSTANCE_ID}" \
    --region "${REGION}" \
    --query "InstanceInformationList[0].PingStatus" \
    --output text 2>/dev/null || echo "Unknown")

  if [ "${STATUS}" = "Online" ]; then
    echo "  Online 확인"
    break
  fi

  if [ "${i}" -eq 30 ]; then
    echo "오류: SSM Agent가 5분 내에 Online 상태가 되지 않았습니다."
    exit 1
  fi

  echo "  대기 중... (${i}/30)"
  sleep 10
done

# ----------------------------------------
# 2. SSM Run Command로 스키마 생성
# ----------------------------------------
echo "[2/3] 모니터링 EC2를 경유해 스키마 생성 명령 전송 중..."

# EC2에서 실행할 명령: SSM에서 비밀번호를 직접 조회하여 psql 실행
REMOTE_CMD="dnf install -y postgresql15 -q 2>/dev/null; \
  DB_PW=\$(aws ssm get-parameter \
    --name ${SSM_PW_PATH} \
    --with-decryption \
    --region ${REGION} \
    --query Parameter.Value \
    --output text); \
  PGPASSWORD=\$DB_PW psql \
    -h ${RDS_HOST} -p 5432 -U ${DB_USER} -d ${DB_NAME} \
    -c 'CREATE SCHEMA IF NOT EXISTS keycloak_schema;' \
    -c 'CREATE SCHEMA IF NOT EXISTS langfuse_schema;' \
  && echo '스키마 생성 완료'"

CMD_ID=$(aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --targets "[{\"Key\":\"instanceids\",\"Values\":[\"${INSTANCE_ID}\"]}]" \
  --parameters "{\"commands\":[\"${REMOTE_CMD}\"]}" \
  --region "${REGION}" \
  --query "Command.CommandId" \
  --output text)

echo "  CommandId: ${CMD_ID}"

# ----------------------------------------
# 3. 결과 대기
# ----------------------------------------
echo "[3/3] 실행 결과 대기 중..."
for i in $(seq 1 24); do
  sleep 5
  STATUS=$(aws ssm get-command-invocation \
    --command-id "${CMD_ID}" \
    --instance-id "${INSTANCE_ID}" \
    --region "${REGION}" \
    --query "Status" \
    --output text 2>/dev/null || echo "Pending")

  echo "  상태: ${STATUS} (${i}/24)"

  if [ "${STATUS}" = "Success" ]; then
    echo "완료. keycloak_schema / langfuse_schema 생성 성공."
    exit 0
  elif [ "${STATUS}" = "Failed" ] || [ "${STATUS}" = "Cancelled" ]; then
    echo "오류: 스키마 생성 실패."
    aws ssm get-command-invocation \
      --command-id "${CMD_ID}" \
      --instance-id "${INSTANCE_ID}" \
      --region "${REGION}" \
      --query "StandardErrorContent" \
      --output text
    exit 1
  fi
done

echo "오류: 시간 초과 (120초). AWS 콘솔에서 직접 확인하세요."
exit 1
