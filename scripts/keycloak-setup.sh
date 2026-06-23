#!/bin/bash
# Keycloak sanjijk realm 설정 스크립트
# terraform apply 후, SSM 복구 후에 실행합니다.
#
# 사용법:
#   bash scripts/keycloak-setup.sh
#
# 전제 조건:
#   - AWS CLI 설치 및 인증 완료
#   - Session Manager Plugin 설치 (aws ssm start-session 사용)
#   - curl, jq 설치
#   - scripts/ssm-restore.sh 실행 완료 (admin-password 복구 필요)

set -euo pipefail

REGION="ap-northeast-2"
REALM_FILE="scripts/realm-export.json"
KEYCLOAK_HOST="keycloak.sanji.local"
KEYCLOAK_PORT="18080"
LOCAL_PORT="18080"
SSM_PARAM_CLIENT_SECRET="/sanji/prod/keycloak/client-secret"

# ----------------------------------------
# 1. 모니터링 EC2 인스턴스 ID 조회
# ----------------------------------------
echo "[1/6] 모니터링 EC2 인스턴스 ID 조회 중..."
MONITORING_ID=$(aws.exe ec2 describe-instances \
  --filters "Name=tag:Role,Values=monitoring" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" \
  --region "${REGION}" \
  --output text | tr -d '\r')

if [ "${MONITORING_ID}" = "None" ] || [ -z "${MONITORING_ID}" ]; then
  echo "오류: 모니터링 EC2를 찾을 수 없습니다."
  exit 1
fi
echo "  인스턴스 ID: ${MONITORING_ID}"

# ----------------------------------------
# 2. SSM 포트 포워딩 시작 (백그라운드)
# ----------------------------------------
echo "[2/6] SSM 포트 포워딩 시작 (localhost:${LOCAL_PORT} -> ${KEYCLOAK_HOST}:${KEYCLOAK_PORT})..."
aws.exe ssm start-session \
  --target "${MONITORING_ID}" \
  --document-name "AWS-StartPortForwardingSessionToRemoteHost" \
  --parameters "{\"host\":[\"${KEYCLOAK_HOST}\"],\"portNumber\":[\"${KEYCLOAK_PORT}\"],\"localPortNumber\":[\"${LOCAL_PORT}\"]}" \
  --region "${REGION}" &
SSM_PID=$!

# 포트 포워딩이 열릴 때까지 대기
echo "  포트 열리는 중..."
for i in $(seq 1 20); do
  sleep 2
  if curl -s --resolve "${KEYCLOAK_HOST}:${KEYCLOAK_PORT}:127.0.0.1" \
    "http://${KEYCLOAK_HOST}:${KEYCLOAK_PORT}/health/ready" > /dev/null 2>&1; then
    echo "  Keycloak 응답 확인."
    break
  fi
  echo "  대기 중... (${i}/20)"
done

# 스크립트 종료 시 포트 포워딩 세션 자동 종료
trap "kill ${SSM_PID} 2>/dev/null; echo '포트 포워딩 종료'" EXIT

# ----------------------------------------
# 3. SSM에서 admin 패스워드 조회
# ----------------------------------------
echo "[3/6] admin 패스워드 조회 중..."
ADMIN_PASSWORD=$(aws.exe ssm get-parameter \
  --name "/sanji/prod/keycloak/admin-password" \
  --with-decryption \
  --region "${REGION}" \
  --query "Parameter.Value" \
  --output text | tr -d '\r')

# ----------------------------------------
# 4. admin 토큰 발급
# ----------------------------------------
echo "[4/6] admin 토큰 발급 중..."
TOKEN=$(curl -s -X POST \
  "http://${KEYCLOAK_HOST}:${KEYCLOAK_PORT}/realms/master/protocol/openid-connect/token" \
  --resolve "${KEYCLOAK_HOST}:${KEYCLOAK_PORT}:127.0.0.1" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password&client_id=admin-cli&username=admin&password=${ADMIN_PASSWORD}" \
  | jq.exe -r '.access_token' | tr -d '\r')

if [ "${TOKEN}" = "null" ] || [ -z "${TOKEN}" ]; then
  echo "오류: 토큰 발급 실패. admin 패스워드를 확인하세요."
  exit 1
fi
echo "  토큰 발급 성공."

# ----------------------------------------
# 5. sanjijk realm import (없을 때만)
# ----------------------------------------
echo "[5/6] sanjijk realm 확인 중..."
REALM_EXISTS=$(curl -s \
  "http://${KEYCLOAK_HOST}:${KEYCLOAK_PORT}/admin/realms/sanjijk" \
  --resolve "${KEYCLOAK_HOST}:${KEYCLOAK_PORT}:127.0.0.1" \
  -H "Authorization: Bearer ${TOKEN}" \
  | jq.exe -r '.realm // empty' | tr -d '\r')

if [ -z "${REALM_EXISTS}" ]; then
  echo "  sanjijk realm 없음 - import 시작..."
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    "http://${KEYCLOAK_HOST}:${KEYCLOAK_PORT}/admin/realms" \
    --resolve "${KEYCLOAK_HOST}:${KEYCLOAK_PORT}:127.0.0.1" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    --data-binary "@${REALM_FILE}")

  if [ "${HTTP_CODE}" != "201" ]; then
    echo "오류: realm import 실패 (HTTP ${HTTP_CODE})"
    exit 1
  fi
  echo "  realm import 완료."
else
  echo "  sanjijk realm 이미 존재. import 건너함."
fi

# ----------------------------------------
# 6. user-service client-secret 재발급 후 SSM 저장
# ----------------------------------------
echo "[6/6] user-service client-secret 재발급 중..."
CLIENT_UUID=$(curl -s \
  "http://${KEYCLOAK_HOST}:${KEYCLOAK_PORT}/admin/realms/sanjijk/clients?clientId=user-service" \
  --resolve "${KEYCLOAK_HOST}:${KEYCLOAK_PORT}:127.0.0.1" \
  -H "Authorization: Bearer ${TOKEN}" \
  | jq.exe -r '.[0].id' | tr -d '\r')

NEW_SECRET=$(curl -s -X POST \
  "http://${KEYCLOAK_HOST}:${KEYCLOAK_PORT}/admin/realms/sanjijk/clients/${CLIENT_UUID}/client-secret" \
  --resolve "${KEYCLOAK_HOST}:${KEYCLOAK_PORT}:127.0.0.1" \
  -H "Authorization: Bearer ${TOKEN}" \
  | jq.exe -r '.value' | tr -d '\r')

echo "  새 client-secret: ${NEW_SECRET}"

aws.exe ssm put-parameter \
  --name "${SSM_PARAM_CLIENT_SECRET}" \
  --value "${NEW_SECRET}" \
  --type "SecureString" \
  --overwrite \
  --region "${REGION}" > /dev/null

echo "  SSM 저장 완료: ${SSM_PARAM_CLIENT_SECRET}"
echo ""
echo "완료. ECS 서비스를 force-redeploy 하세요."
