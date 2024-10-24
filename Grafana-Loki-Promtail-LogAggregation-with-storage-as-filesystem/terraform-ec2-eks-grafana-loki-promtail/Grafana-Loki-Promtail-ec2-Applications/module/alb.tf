########################################################## Grafana Application LoadBalancer ##############################################################

# Security Group for ALB
resource "aws_security_group" "grafana_alb" {
  name        = "Grafana-ALB"
  description = "Security Group for Grafana ALB"
  vpc_id      = var.vpc_id

  ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = var.cidr_blocks
  }

  ingress {
    protocol   = "tcp"
    cidr_blocks = var.cidr_blocks
    from_port  = 80
    to_port    = 80
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Grafana-ALB-sg"
  }
}

#S3 Bucket to capture Grafana ALB access logs
resource "aws_s3_bucket" "s3_bucket_grafana" {
  count = var.s3_bucket_exists == false ? 1 : 0
  bucket = var.access_log_bucket_grafana

  force_destroy = true

  tags = {
    Environment = var.env
  }
}

#S3 Bucket Server Side Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "s3bucket_encryption_grafana" {
  count = var.s3_bucket_exists == false ? 1 : 0
  bucket = aws_s3_bucket.s3_bucket_grafana[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "AES256"
    }
  }
}

#Apply Bucket Policy to S3 Bucket
resource "aws_s3_bucket_policy" "s3bucket_policy_grafana" {
  count = var.s3_bucket_exists == false ? 1 : 0
  bucket = aws_s3_bucket.s3_bucket_grafana[0].id
  policy = file("bucket-policy_grafana.json")

  depends_on = [aws_s3_bucket_server_side_encryption_configuration.s3bucket_encryption_grafana]
}

#Application Loadbalancer
resource "aws_lb" "test-application-loadbalancer_grafana" {
  name               = var.application_loadbalancer_name
  internal           = var.internal
  load_balancer_type = var.load_balancer_type
  security_groups    = [aws_security_group.grafana_alb.id]           ###var.security_groups
  subnets            = var.subnets

  enable_deletion_protection = var.enable_deletion_protection
  idle_timeout = var.idle_timeout
  access_logs {
    bucket  = var.access_log_bucket_grafana
    prefix  = var.prefix
    enabled = var.enabled
  }

  tags = {
    Environment = var.env
  }

  depends_on = [aws_s3_bucket_policy.s3bucket_policy_grafana]
}

#Target Group of Application Loadbalancer Grafana
resource "aws_lb_target_group" "target_group_grafana" {
  name     = var.target_group_name
  port     = var.instance_port      ##### Don't use protocol when target type is lambda
  protocol = var.instance_protocol  ##### Don't use protocol when target type is lambda
  vpc_id   = var.vpc_id
  target_type = var.target_type_alb
  load_balancing_algorithm_type = var.load_balancing_algorithm_type
  health_check {
    enabled = true ## Indicates whether health checks are enabled. Defaults to true.
    path = var.healthcheck_path     ###"/index.html"
    port = "traffic-port"
    protocol = "HTTP"
    healthy_threshold   = var.healthy_threshold
    unhealthy_threshold = var.unhealthy_threshold
    timeout             = var.timeout
    interval            = var.interval
  }
}

##Grafana Application Loadbalancer listener for HTTP
resource "aws_lb_listener" "alb_listener_front_end_HTTP_grafana" {
  load_balancer_arn = aws_lb.test-application-loadbalancer_grafana.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = var.type[1]
    target_group_arn = aws_lb_target_group.target_group_grafana.arn
     redirect {    ### Redirect HTTP to HTTPS
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

##Grafana Application Loadbalancer listener for HTTPS
resource "aws_lb_listener" "alb_listener_front_end_HTTPS_grafana" {
  load_balancer_arn = aws_lb.test-application-loadbalancer_grafana.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn

  default_action {
    type             = var.type[0]
    target_group_arn = aws_lb_target_group.target_group_grafana.arn
  }
}

## EC2 Instance1 attachment to Grafana Target Group
resource "aws_lb_target_group_attachment" "ec2_instance1_attachment_to_tg_grafana" {
  target_group_arn = aws_lb_target_group.target_group_grafana.arn
  target_id        = aws_instance.grafana.id               #var.ec2_instance_id[0]
  port             = var.instance_port
}

## EC2 Instance2 attachment to Target Group
#resource "aws_lb_target_group_attachment" "ec2_instance2_attachment_to_tg" {
#  target_group_arn = aws_lb_target_group.target_group.arn
#  target_id        = var.ec2_instance_id[1]
#  port             = var.instance_port
#}

###################################################### Loki Application LoadBalancer #############################################################

# Security Group for Loki ALB
resource "aws_security_group" "loki_alb" {
  name        = "Loki-ALB"
  description = "Security Group for Loki ALB"
  vpc_id      = var.vpc_id

  ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = var.cidr_blocks
  }

  ingress {
    protocol   = "tcp"
    cidr_blocks = var.cidr_blocks
    from_port  = 80
    to_port    = 80
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Loki-ALB-sg"
  }
}

#S3 Bucket to capture Loki ALB access logs
resource "aws_s3_bucket" "s3_bucket_loki" {
  count = var.s3_bucket_exists == false ? 1 : 0
  bucket = var.access_log_bucket_loki

  force_destroy = true

  tags = {
    Environment = var.env
  }
}

#S3 Bucket Loki Server Side Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "s3bucket_encryption_loki" {
  count = var.s3_bucket_exists == false ? 1 : 0
  bucket = aws_s3_bucket.s3_bucket_loki[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "AES256"
    }
  }
}

#Apply Bucket Policy to Loki S3 Bucket
resource "aws_s3_bucket_policy" "s3bucket_policy_loki" {
  count = var.s3_bucket_exists == false ? 1 : 0
  bucket = aws_s3_bucket.s3_bucket_loki[0].id
  policy = file("bucket-policy_loki.json")

  depends_on = [aws_s3_bucket_server_side_encryption_configuration.s3bucket_encryption_loki]
}

#Loki Application Loadbalancer
resource "aws_lb" "test-application-loadbalancer_loki" {
  name               = "Loki"
  internal           = var.internal
  load_balancer_type = var.load_balancer_type
  security_groups    = [aws_security_group.loki_alb.id]           ###var.security_groups
  subnets            = var.subnets

  enable_deletion_protection = var.enable_deletion_protection
  idle_timeout = var.idle_timeout
  access_logs {
    bucket  = var.access_log_bucket_loki
    prefix  = var.prefix
    enabled = var.enabled
  }

  tags = {
    Environment = var.env
  }

  depends_on = [aws_s3_bucket_policy.s3bucket_policy_loki]
}

#Target Group of Loki Application Loadbalancer
resource "aws_lb_target_group" "target_group_loki" {
  name     = "Loki"
  port     = "3100"    ###var.instance_port      ##### Don't use protocol when target type is lambda
  protocol = var.instance_protocol  ##### Don't use protocol when target type is lambda
  vpc_id   = var.vpc_id
  target_type = var.target_type_alb
  load_balancing_algorithm_type = var.load_balancing_algorithm_type
  health_check {
    enabled = true ## Indicates whether health checks are enabled. Defaults to true.
    path = "/ready"    ###var.healthcheck_path     ###"/index.html"
    port = "traffic-port"
    protocol = "HTTP"
    healthy_threshold   = var.healthy_threshold
    unhealthy_threshold = var.unhealthy_threshold
    timeout             = var.timeout
    interval            = var.interval
  }
}

##Application Loadbalancer listener for HTTP
resource "aws_lb_listener" "alb_listener_front_end_HTTP_loki" {
  load_balancer_arn = aws_lb.test-application-loadbalancer_loki.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = var.type[0]
    target_group_arn = aws_lb_target_group.target_group_loki.arn
  }
}

#  default_action {
#    type             = var.type[1]
#    target_group_arn = aws_lb_target_group.target_group_loki.arn
#     redirect {    ### Redirect HTTP to HTTPS
#      port        = "443"
#      protocol    = "HTTPS"
#      status_code = "HTTP_301"
#    }
#  }
#}

##Application Loadbalancer listener for HTTPS
resource "aws_lb_listener" "alb_listener_front_end_HTTPS_loki" {
  load_balancer_arn = aws_lb.test-application-loadbalancer_loki.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn

  default_action {
    type             = var.type[0]
    target_group_arn = aws_lb_target_group.target_group_loki.arn
  }
}

## EC2 Instance1 attachment to Target Group
resource "aws_lb_target_group_attachment" "ec2_instance1_attachment_to_tg_loki" {
  target_group_arn = aws_lb_target_group.target_group_loki.arn
  target_id        = aws_instance.loki[0].id               #var.ec2_instance_id[0]
  port             = "3100"    ###var.instance_port
}

## EC2 Instance2 attachment to Target Group
resource "aws_lb_target_group_attachment" "ec2_instance2_attachment_to_tg_loki" {
  target_group_arn = aws_lb_target_group.target_group_loki.arn
  target_id        = aws_instance.loki[1].id               #var.ec2_instance_id[1]
  port             = "3100"    ###var.instance_port
}

## EC2 Instance3 attachment to Target Group
resource "aws_lb_target_group_attachment" "ec2_instance3_attachment_to_tg_loki" {
  target_group_arn = aws_lb_target_group.target_group_loki.arn
  target_id        = aws_instance.loki[2].id               #var.ec2_instance_id[2]
  port             = "3100"    ###var.instance_port
}
