#!/bin/bash
# Redis 접속용 SSM 포트포워딩 스크립트
#
# Redis(ElastiCache)는 Private Subnet에 있어 외부에서 직접 접속할 수 없습니다.
# 모니터링 EC2를 징검다리로 삼아 SSM 포트포워딩으로 로컬 포트를 Redis에 연결합니다.
# 별도 Bastion 서버나 SSH 키가 필요 없습니다.
#
# 사용법:
#   bash scripts/connect-redis.sh <dev|prod> [로컬포트]
#
# 예시:
#   bash scripts/connect-redis.sh dev
#   bash scripts/connect-redis.sh prod 16379
#
# 전제 조건:
#   - AWS CLI, Session Manager 플러그인 설치 및 인증 완료
#   - 모니터링 EC2가 실행 중이고 SSM Agent가 Online 상태
#
# 세션이 열리면 다른 터미널에서 아래처럼 접속합니다:
#   redis-cli -h 127.0.0.1 -p <로컬포트>

set -euo pipefail

REGION="ap-northeast-2"
PROJECT="sanji"
REMOTE_PORT=6379

ENVIRONMENT="${1:-}"
LOCAL_PORT="${2:-6379}"

if [ "${ENVIRONMENT}" != "dev" ] && [ "${ENVIRONMENT}" != "prod" ]; then
  echo "사용법: bash scripts/connect-redis.sh <dev|prod> [로컬포트]"
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
# 2. Redis 엔드포인트 조회
# ----------------------------------------
echo "[2/3] Redis 엔드포인트 조회 중..."

REDIS_HOST=$(aws.exe elasticache describe-cache-clusters \
  --cache-cluster-id "${PROJECT}-${ENVIRONMENT}-redis" \
  --show-cache-node-info \
  --query "CacheClusters[0].CacheNodes[0].Endpoint.Address" \
  --region "${REGION}" \
  --output text | tr -d '\r')

if [ -z "${REDIS_HOST}" ] || [ "${REDIS_HOST}" = "None" ]; then
  echo "오류: Redis 엔드포인트를 찾을 수 없습니다."
  exit 1
fi
echo "  Redis 엔드포인트: ${REDIS_HOST}"

# ----------------------------------------
# 3. SSM 포트포워딩 세션 시작
# ----------------------------------------
echo "[3/3] SSM 포트포워딩 세션 시작 (localhost:${LOCAL_PORT} -> ${REDIS_HOST}:${REMOTE_PORT})"
echo "  종료하려면 Ctrl+C를 누르세요."

aws.exe ssm start-session \
  --target "${MONITORING_ID}" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"${REDIS_HOST}\"],\"portNumber\":[\"${REMOTE_PORT}\"],\"localPortNumber\":[\"${LOCAL_PORT}\"]}" \
  --region "${REGION}"
