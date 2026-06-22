# ============================================================================
# 네트워크: VPC, 서브넷, 인터넷 게이트웨이, 라우팅
# ============================================================================
# NAT Gateway 없음. 퍼블릭 서브넷 + 인터넷 게이트웨이로 직접 아웃바운드.
# 보안은 NAT가 아니라 "보안 그룹 인바운드 차단"으로 지킵니다. (security_groups.tf)

# VPC: 우리만의 격리된 가상 네트워크 (집 한 채라고 생각하면 됩니다)
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true # 서비스 디스커버리(Cloud Map) DNS가 동작하려면 필요

  tags = { Name = "${local.name}-vpc" }
}

# 인터넷 게이트웨이: VPC를 인터넷과 연결하는 문 (NAT 대신 이걸로 직접 나갑니다)
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name}-igw" }
}

# --- 퍼블릭 서브넷 ---
# ALB, ECS 태스크, Kafka/모니터링 EC2가 들어갑니다.
# availability_zones 맵을 한 바퀴 돌며 AZ마다 하나씩 만듭니다.
resource "aws_subnet" "public" {
  for_each = var.availability_zones

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.public_cidr
  availability_zone       = each.key
  map_public_ip_on_launch = true # 여기 뜨는 자원은 공인 IP를 자동으로 받음 (아웃바운드용)

  tags = { Name = "${local.name}-public-${each.key}" }
}

# --- 프라이빗 서브넷 ---
# RDS, ElastiCache(Redis)가 들어갑니다. 외부에서 직접 닿을 수 없습니다.
resource "aws_subnet" "private" {
  for_each = var.availability_zones

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.private_cidr
  availability_zone = each.key

  tags = { Name = "${local.name}-private-${each.key}" }
}

# --- 라우팅 테이블 ---
# 라우팅 테이블은 "어디로 가는 트래픽을 어느 문으로 보낼지" 적은 표입니다.

# 퍼블릭: 외부(0.0.0.0/0)로 가는 트래픽은 인터넷 게이트웨이로 보냄
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${local.name}-public-rt" }
}

# 퍼블릭 서브넷들을 위 라우팅 테이블에 연결
resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# 프라이빗: 인터넷으로 나가는 경로가 없음(라우팅 없음).
# RDS/Redis는 외부와 통신할 필요가 없으므로 VPC 내부 통신만 가능합니다.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name}-private-rt" }
}

resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}
