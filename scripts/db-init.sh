#!/bin/bash
# RDS 스키마 초기화 스크립트
# terraform apply 후에 실행합니다.
#
# 사용법:
#   bash scripts/db-init.sh
#
# 전제 조건:
#   - AWS CLI 설치 및 인증 완료
#   - Kafka EC2가 실행 중이고 SSM Agent가 Online 상태
#   - RDS가 생성 완료된 상태
#   - Kafka EC2에 sanji-jk 저장소가 배포되어 있어야 함 (db/init/*.sql 존재)

set -euo pipefail

REGION="ap-northeast-2"

# ----------------------------------------
# 1. 필요한 값 조회
# ----------------------------------------
echo "[1/3] 환경 정보 조회 중..."

KAFKA_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Role,Values=kafka" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" \
  --region "${REGION}" \
  --output text)

if [ "${KAFKA_ID}" = "None" ] || [ -z "${KAFKA_ID}" ]; then
  echo "오류: Kafka EC2를 찾을 수 없습니다."
  exit 1
fi
echo "  Kafka EC2: ${KAFKA_ID}"

RDS_HOST=$(aws rds describe-db-instances \
  --query "DBInstances[?DBInstanceIdentifier=='sanji-prod-postgres'].Endpoint.Address" \
  --region "${REGION}" \
  --output text)

if [ -z "${RDS_HOST}" ]; then
  echo "오류: RDS 엔드포인트를 찾을 수 없습니다."
  exit 1
fi
echo "  RDS 엔드포인트: ${RDS_HOST}"

DB_PASSWORD=$(aws ssm get-parameter \
  --name "/sanji/prod/db-password" \
  --with-decryption \
  --region "${REGION}" \
  --query "Parameter.Value" \
  --output text)

# ----------------------------------------
# 2. SSM Run Command 실행
# ----------------------------------------
echo "[2/3] Kafka EC2에서 스키마 초기화 실행 중..."

CMD="dnf install -y postgresql15 -q && \
  export PGPASSWORD='${DB_PASSWORD}' && \
  for f in /home/ec2-user/sanji-jk/db/init/*.sql; do \
    echo \"Running \$f\"; \
    psql -h ${RDS_HOST} -p 5432 -U sanji -d sanji -f \$f; \
  done && \
  echo 'Schema init complete'"

CMD_ID=$(aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --targets "[{\"Key\":\"instanceids\",\"Values\":[\"${KAFKA_ID}\"]}]" \
  --parameters "{\"commands\":[\"${CMD}\"]}" \
  --region "${REGION}" \
  --query "Command.CommandId" \
  --output text)

echo "  CommandId: ${CMD_ID}"

# ----------------------------------------
# 3. 결과 대기 및 확인
# ----------------------------------------
echo "[3/3] 실행 결과 대기 중..."
for i in $(seq 1 30); do
  sleep 5
  STATUS=$(aws ssm get-command-invocation \
    --command-id "${CMD_ID}" \
    --instance-id "${KAFKA_ID}" \
    --region "${REGION}" \
    --query "Status" \
    --output text 2>/dev/null || echo "Pending")

  echo "  상태: ${STATUS} (${i}/30)"

  if [ "${STATUS}" = "Success" ]; then
    echo ""
    echo "완료. 스키마 초기화 성공."
    exit 0
  elif [ "${STATUS}" = "Failed" ] || [ "${STATUS}" = "Cancelled" ]; then
    echo ""
    echo "오류: 스키마 초기화 실패."
    aws ssm get-command-invocation \
      --command-id "${CMD_ID}" \
      --instance-id "${KAFKA_ID}" \
      --region "${REGION}" \
      --query "StandardErrorContent" \
      --output text
    exit 1
  fi
done

echo "오류: 시간 초과 (150초). AWS 콘솔에서 직접 확인하세요."
exit 1
