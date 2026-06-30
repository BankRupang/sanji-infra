#!/bin/bash
# [비상 복구용] RDS 스키마 수동 초기화 스크립트
#
# 정상 운영 시에는 terraform apply가 null_resource(db_schema_init)를 통해
# db-schema-init.sh를 자동 실행합니다. 이 스크립트는 자동화가 실패했을 때
# 수동으로 keycloak_schema / langfuse_schema를 생성하는 용도로만 사용합니다.
#
# 사용법:
#   bash scripts/db-init.sh
#
# 전제 조건:
#   - AWS CLI 설치 및 인증 완료
#   - 모니터링 EC2가 실행 중이고 SSM Agent가 Online 상태
#   - RDS가 생성 완료된 상태
#   - 모니터링 EC2 /home/ec2-user/deploy/db/init/*.sql 파일이 있어야 함

set -euo pipefail

REGION="ap-northeast-2"

# ----------------------------------------
# 1. 필요한 값 조회
# ----------------------------------------
echo "[1/3] 환경 정보 조회 중..."

MONITORING_ID=$(aws.exe ec2 describe-instances \
  --filters "Name=tag:Role,Values=monitoring" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" \
  --region "${REGION}" \
  --output text | tr -d '\r')

if [ "${MONITORING_ID}" = "None" ] || [ -z "${MONITORING_ID}" ]; then
  echo "오류: 모니터링 EC2를 찾을 수 없습니다."
  exit 1
fi
echo "  모니터링 EC2: ${MONITORING_ID}"

RDS_HOST=$(aws.exe rds describe-db-instances \
  --query "DBInstances[?DBInstanceIdentifier=='sanji-prod-postgres'].Endpoint.Address" \
  --region "${REGION}" \
  --output text | tr -d '\r')

if [ -z "${RDS_HOST}" ]; then
  echo "오류: RDS 엔드포인트를 찾을 수 없습니다."
  exit 1
fi
echo "  RDS 엔드포인트: ${RDS_HOST}"

DB_PASSWORD=$(aws.exe ssm get-parameter \
  --name "/sanji/prod/db/password" \
  --with-decryption \
  --region "${REGION}" \
  --query "Parameter.Value" \
  --output text | tr -d '\r')

# ----------------------------------------
# 2. SSM Run Command 실행
# ----------------------------------------
echo "[2/3] 모니터링 EC2에서 스키마 초기화 실행 중..."

CMD="dnf install -y postgresql15 -q && \
  export PGPASSWORD='${DB_PASSWORD}' && \
  for f in /home/ec2-user/deploy/db/init/*.sql; do \
    printf 'Running %s\n' \$f; \
    psql -h ${RDS_HOST} -p 5432 -U sanji -d sanji -f \$f; \
  done && \
  echo 'Schema init complete'"

CMD_ID=$(aws.exe ssm send-command \
  --document-name "AWS-RunShellScript" \
  --targets "[{\"Key\":\"instanceids\",\"Values\":[\"${MONITORING_ID}\"]}]" \
  --parameters "{\"commands\":[\"${CMD}\"]}" \
  --region "${REGION}" \
  --query "Command.CommandId" \
  --output text | tr -d '\r')

echo "  CommandId: ${CMD_ID}"

# ----------------------------------------
# 3. 결과 대기 및 확인
# ----------------------------------------
echo "[3/3] 실행 결과 대기 중..."
for i in $(seq 1 30); do
  sleep 5
  STATUS=$( (aws.exe ssm get-command-invocation \
    --command-id "${CMD_ID}" \
    --instance-id "${MONITORING_ID}" \
    --region "${REGION}" \
    --query "Status" \
    --output text 2>/dev/null || echo "Pending") | tr -d '\r' )

  echo "  상태: ${STATUS} (${i}/30)"

  if [ "${STATUS}" = "Success" ]; then
    echo ""
    echo "완료. 스키마 초기화 성공."
    exit 0
  elif [ "${STATUS}" = "Failed" ] || [ "${STATUS}" = "Cancelled" ]; then
    echo ""
    echo "오류: 스키마 초기화 실패."
    aws.exe ssm get-command-invocation \
      --command-id "${CMD_ID}" \
      --instance-id "${MONITORING_ID}" \
      --region "${REGION}" \
      --query "StandardErrorContent" \
      --output text
    exit 1
  fi
done

echo "오류: 시간 초과 (150초). AWS 콘솔에서 직접 확인하세요."
exit 1
