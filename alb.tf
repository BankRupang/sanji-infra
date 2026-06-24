# ============================================================================
# ALB: 애플리케이션 로드밸런서 (유일한 외부 진입점)
# ============================================================================
# ALB는 gateway-server 한 곳으로만 트래픽을 보냅니다.
# 입찰 WebSocket도 gateway를 거쳐 내부 bid 서비스로 연결됩니다.

resource "aws_lb" "main" {
  name               = "${local.name}-alb"
  load_balancer_type = "application"
  internal           = false # 인터넷에서 접근 가능
  security_groups    = [aws_security_group.alb.id]
  # ALB는 규칙상 최소 2개 AZ의 서브넷이 필요함
  subnets = [for s in aws_subnet.public : s.id]

  tags = { Name = "${local.name}-alb" }
}

# 대상 그룹: ALB가 트래픽을 보낼 목적지 묶음 (gateway 태스크들)
resource "aws_lb_target_group" "gateway" {
  name        = "${local.name}-gateway-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip" # Fargate(awsvpc)는 IP로 등록됨

  # 헬스체크 200 통과하면 정상으로 판단하고 트래픽을 보냅니다.
  health_check {
    path                = "/actuator/health"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  # WebSocket 연결이 같은 gateway 태스크로 유지되도록
  stickiness {
    type            = "lb_cookie"
    cookie_duration = 3600
    enabled         = true
  }

  # 태스크 교체 시 기존 연결을 정리할 여유 시간
  deregistration_delay = 120
}

# HTTP(80) 리스너
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  # 인증서가 있으면 HTTP는 HTTPS로 자동 리다이렉트, 없으면 그대로 gateway로 전달
  default_action {
    type             = var.acm_certificate_arn != "" ? "redirect" : "forward"
    target_group_arn = var.acm_certificate_arn != "" ? null : aws_lb_target_group.gateway.arn

    dynamic "redirect" {
      for_each = var.acm_certificate_arn != "" ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }
}

# HTTPS(443) 리스너: ACM 인증서 ARN을 변수로 넣었을 때만 생성됩니다.
resource "aws_lb_listener" "https" {
  count             = var.acm_certificate_arn != "" ? 1 : 0
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gateway.arn
  }
}
