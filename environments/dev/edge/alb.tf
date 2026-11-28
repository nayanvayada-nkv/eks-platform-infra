# ---------------------------------------------------------------------------
# Internal ALB. No public IP, no internet listener: the only way in is CloudFront,
# through a VPC origin (CloudFront places its own network interfaces in our private subnets).
# Targets (Istio ingress gateway pods) are registered by the AWS Load Balancer Controller
# from a TargetGroupBinding in gitops/platform/ingress.
# ---------------------------------------------------------------------------
resource "aws_lb" "internal" {
  #checkov:skip=CKV_AWS_91:Access logs come with the Phase 6 logging bucket; CloudFront and WAF already log the edge
  #checkov:skip=CKV_AWS_150:Deletion protection off in dev so the test run can be destroyed
  #checkov:skip=CKV2_AWS_28:The WAF is attached to CloudFront, the only path to this internal ALB
  #checkov:skip=CKV2_AWS_20:Internal ALB behind CloudFront, which redirects viewers to HTTPS
  name                       = "${local.name}-edge"
  internal                   = true
  load_balancer_type         = "application"
  subnets                    = local.network.private_subnet_ids
  security_groups            = [aws_security_group.alb.id]
  drop_invalid_header_fields = true # request smuggling defence
  desync_mitigation_mode     = "strictest"
}

resource "aws_lb_target_group" "gateway" {
  #checkov:skip=CKV_AWS_378:HTTP inside the VPC between ALB and the Istio gateway; viewers use HTTPS to CloudFront
  name        = "${local.name}-istio-gw"
  target_type = "ip" # pod IPs, no NodePort
  port        = 80
  protocol    = "HTTP"
  vpc_id      = local.network.vpc_id

  health_check {
    port    = "15021" # Istio gateway readiness port
    path    = "/healthz/ready"
    matcher = "200"
  }

  deregistration_delay = 15 # dev: fast rollouts
}

resource "aws_lb_listener" "http" {
  #checkov:skip=CKV_AWS_2:Internal listener reached only by the CloudFront VPC origin; TLS terminates at CloudFront
  #checkov:skip=CKV_AWS_103:Same as CKV_AWS_2, no TLS on this internal hop
  load_balancer_arn = aws_lb.internal.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gateway.arn
  }
}

resource "aws_security_group" "alb" {
  name        = "${local.name}-edge-alb"
  description = "Internal ALB: from CloudFront VPC origin only; to gateway pods only"
  vpc_id      = local.network.vpc_id
  tags        = { Name = "${local.name}-edge-alb" }
}

# CloudFront creates this security group in our VPC when the first VPC origin is made.
data "aws_security_group" "cloudfront_vpc_origins" {
  vpc_id = local.network.vpc_id
  name   = "CloudFront-VPCOrigins-Service-SG"

  depends_on = [aws_cloudfront_vpc_origin.alb]
}

resource "aws_vpc_security_group_ingress_rule" "alb_from_cloudfront" {
  #checkov:skip=CKV_AWS_260:Source is the CloudFront VPC origin security group, not 0.0.0.0/0 (Checkov cannot resolve the data source)
  security_group_id            = aws_security_group.alb.id
  description                  = "HTTP from CloudFront VPC origin ENIs"
  referenced_security_group_id = data.aws_security_group.cloudfront_vpc_origins.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

# To the gateway pods (pod IPs are VPC addresses): traffic and health checks.
resource "aws_vpc_security_group_egress_rule" "alb_to_gateway" {
  for_each          = { traffic = 80, health = 15021 }
  security_group_id = aws_security_group.alb.id
  description       = "To Istio gateway pods (${each.key})"
  cidr_ipv4         = local.network.vpc_cidr_block
  ip_protocol       = "tcp"
  from_port         = each.value
  to_port           = each.value
}
