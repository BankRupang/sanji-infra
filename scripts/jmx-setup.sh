#!/bin/bash
# Kafka EC2에 JMX Exporter JAR 다운로드
# terraform apply 후, Deploy EC2 완료 후에 실행합니다.
#
# 사용법:
#   bash scripts/jmx-setup.sh
#
# 전제 조건:
#   - AWS CLI 설치 및 인증 완료
#   - Kafka EC2가 실행 중이고 SSM Agent가 Online 상태

set -euo pipefail

REGION="ap-northeast-2"
JMX_VERSION="1.0.1"
JMX_JAR="jmx_prometheus_javaagent-${JMX_VERSION}.jar"
JMX_URL="https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/${JMX_VERSION}/${JMX_JAR}"
JMX_DIR="/home/ec2-user/sanji-jk/jmx"

# ----------------------------------------
# 1. Kafka EC2 인스턴스 ID 조회
# ----------------------------------------
echo "[1/2] Kafka EC2 인스턴스 ID 조회 중..."
KAFKA_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Role,Values=kafka" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" \
  --region "${REGION}" \
  --output text)

if [ "${KAFKA_ID}" = "None" ] || [ -z "${KAFKA_ID}" ]; then
  echo "오류: Kafka EC2를 찾을 수 없습니다."
  exit 1
fi
echo "  인스턴스 ID: ${KAFKA_ID}"

# ----------------------------------------
# 2. JMX Exporter JAR 다운로드
# ----------------------------------------
echo "[2/2] JMX Exporter JAR 다운로드 중... (${JMX_JAR})"

CMD_ID=$(aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --targets "[{\"Key\":\"instanceids\",\"Values\":[\"${KAFKA_ID}\"]}]" \
  --parameters "{\"commands\":[\"mkdir -p ${JMX_DIR} && wget -q -O ${JMX_DIR}/${JMX_JAR} ${JMX_URL} && echo OK\"]}" \
  --region "${REGION}" \
  --query "Command.CommandId" \
  --output text)

echo "  CommandId: ${CMD_ID}"

for i in $(seq 1 20); do
  sleep 5
  STATUS=$(aws ssm get-command-invocation \
    --command-id "${CMD_ID}" \
    --instance-id "${KAFKA_ID}" \
    --region "${REGION}" \
    --query "Status" \
    --output text 2>/dev/null || echo "Pending")

  echo "  상태: ${STATUS} (${i}/20)"

  if [ "${STATUS}" = "Success" ]; then
    echo ""
    echo "완료. JMX Exporter JAR 다운로드 성공."
    echo "  경로: ${JMX_DIR}/${JMX_JAR}"
    exit 0
  elif [ "${STATUS}" = "Failed" ] || [ "${STATUS}" = "Cancelled" ]; then
    echo ""
    echo "오류: 다운로드 실패."
    aws ssm get-command-invocation \
      --command-id "${CMD_ID}" \
      --instance-id "${KAFKA_ID}" \
      --region "${REGION}" \
      --query "StandardErrorContent" \
      --output text
    exit 1
  fi
done

echo "오류: 시간 초과 (100초)."
exit 1
