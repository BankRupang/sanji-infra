# ============================================================================
# ALB: 애플리케이션 로드밸런서 (유일한 외부 진입점)
# ============================================================================

resource "aws_lb" "main" {
  name               = "${var.name}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [var.sg_alb_id]
  subnets            = var.public_subnet_ids

  tags = { Name = "${var.name}-alb" }
}

resource "aws_lb_target_group" "gateway" {
  name        = "${var.name}-gateway-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

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

  deregistration_delay = 120
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

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
