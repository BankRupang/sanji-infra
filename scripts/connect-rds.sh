#!/bin/bash
# RDS 접속용 SSM 포트포워딩 스크립트
#
# RDS는 Private Subnet에 있어 외부에서 직접 접속할 수 없습니다.
# 모니터링 EC2를 징검다리로 삼아 SSM 포트포워딩으로 로컬 포트를 RDS에 연결합니다.
# 별도 Bastion 서버나 SSH 키가 필요 없습니다.
#
# 사용법:
#   bash scripts/connect-rds.sh <dev|prod> [로컬포트]
#
# 예시:
#   bash scripts/connect-rds.sh dev
#   bash scripts/connect-rds.sh prod 15432
#
# 전제 조건:
#   - AWS CLI, Session Manager 플러그인 설치 및 인증 완료
#   - 모니터링 EC2가 실행 중이고 SSM Agent가 Online 상태
#
# 세션이 열리면 다른 터미널에서 아래처럼 접속합니다.
# (RDS 기본 파라미터 그룹이 SSL을 강제하므로 sslmode=require가 필요합니다)
#   psql "host=127.0.0.1 port=<로컬포트> user=sanji dbname=sanji sslmode=require"
#
# 비밀번호는 SSM에 있습니다:
#   aws.exe ssm get-parameter --name "/sanji/<dev|prod>/db/password" --with-decryption --region ap-northeast-2 --query "Parameter.Value" --output text

set -euo pipefail

REGION="ap-northeast-2"
PROJECT="sanji"
REMOTE_PORT=5432

ENVIRONMENT="${1:-}"
LOCAL_PORT="${2:-5432}"

if [ "${ENVIRONMENT}" != "dev" ] && [ "${ENVIRONMENT}" != "prod" ]; then
  echo "사용법: bash scripts/connect-rds.sh <dev|prod> [로컬포트]"
  exit 1
fi

# ----------------------------------------
# 1. 모니터링 EC2 조회
# ----------------------------------------
echo "[1/3] ${ENVIRONMENT} 모니터링 EC2 조회 중..."

MONITORING_ID=$(aws.exe ec2 describe-instances \
  --filters "Name=tag:Role,Values=monitoring" "Name=tag:Environment,Values=${ENVIRONMENT}" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" \
  --region "${REGION}" \
  --output text | tr -d '\r')

if [ "${MONITORING_ID}" = "None" ] || [ -z "${MONITORING_ID}" ]; then
  echo "오류: ${ENVIRONMENT} 환경의 모니터링 EC2를 찾을 수 없습니다."
  exit 1
fi
echo "  모니터링 EC2: ${MONITORING_ID}"

# ----------------------------------------
# 2. RDS 엔드포인트 조회
# ----------------------------------------
echo "[2/3] RDS 엔드포인트 조회 중..."

RDS_HOST=$(aws.exe rds describe-db-instances \
  --query "DBInstances[?DBInstanceIdentifier=='${PROJECT}-${ENVIRONMENT}-postgres'].Endpoint.Address" \
  --region "${REGION}" \
  --output text | tr -d '\r')

if [ -z "${RDS_HOST}" ]; then
  echo "오류: RDS 엔드포인트를 찾을 수 없습니다."
  exit 1
fi
echo "  RDS 엔드포인트: ${RDS_HOST}"

# ----------------------------------------
# 3. SSM 포트포워딩 세션 시작
# ----------------------------------------
echo "[3/3] SSM 포트포워딩 세션 시작 (localhost:${LOCAL_PORT} -> ${RDS_HOST}:${REMOTE_PORT})"
echo "  종료하려면 Ctrl+C를 누르세요."

aws.exe ssm start-session \
  --target "${MONITORING_ID}" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"${RDS_HOST}\"],\"portNumber\":[\"${REMOTE_PORT}\"],\"localPortNumber\":[\"${LOCAL_PORT}\"]}" \
  --region "${REGION}"
