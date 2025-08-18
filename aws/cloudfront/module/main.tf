locals {
  s3_origin_id = "publicOrigin"
  default_origin = {
    for k, v in var.nitric.origins : k => v
    if v.path == "/"
  }
  s3_bucket_origins = {
    for k, v in var.nitric.origins : k => v
    if contains(keys(v.resources), "aws_s3_bucket")
  }
  lambda_origins = {
    for k, v in var.nitric.origins : k => v
    if contains(keys(v.resources), "aws_lambda_function")
  }
  non_vpc_origins = {
    for k, v in var.nitric.origins : k => v
    if !contains(keys(v.resources), "aws_lb")
  }
  vpc_origins = {
    for k, v in var.nitric.origins : k => v
    if contains(keys(v.resources), "aws_lb")
  }
}

resource "aws_cloudfront_vpc_origin" "vpc_origin" {
  for_each = local.vpc_origins

  vpc_origin_endpoint_config {
    name = each.key
    arn = each.value.resources["aws_lb"]
    http_port = each.value.resources["aws_lb:http_port"]
    # Doesn't matter what we set this to, it's not used
    # But 0 is not a legal value
    https_port = 443
    origin_protocol_policy = "http-only"

    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }
}

data "aws_ec2_managed_prefix_list" "cloudfront" {
 name = "com.amazonaws.global.cloudfront.origin-facing"
}

# Allow the cloudfront instance the ability to access the load balancer
resource "aws_security_group_rule" "ingress" {
  for_each = local.vpc_origins
  # FIXME: Only apply to a mutual security that is shared with the ALB
  security_group_id = each.value.resources["aws_lb:security_group"]
  # self = true
  from_port = each.value.resources["aws_lb:http_port"]
  to_port = each.value.resources["aws_lb:http_port"]
  protocol = "tcp"
  type = "ingress"

  prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id]
}

resource "aws_cloudfront_origin_access_control" "lambda_oac" {
  count = length(local.lambda_origins) > 0 ? 1 : 0

  name                              = "lambda-oac"
  origin_access_control_origin_type = "lambda"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_origin_access_control" "s3_oac" {
  count = length(local.s3_bucket_origins) > 0 ? 1 : 0

  name                              = "s3-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Allow cloudfront to execute the function urls of any provided AWS lambda functions
resource "aws_lambda_permission" "allow_cloudfront_to_execute_lambda" {
  for_each = local.lambda_origins

  function_name = each.value.resources["aws_lambda_function"]
  principal = "cloudfront.amazonaws.com"
  action = "lambda:InvokeFunctionUrl"
  source_arn = aws_cloudfront_distribution.distribution.arn
}

resource "aws_s3_bucket_policy" "allow_bucket_access" {
  for_each = local.s3_bucket_origins

  bucket = replace(each.value.id, "arn:aws:s3:::", "")

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action = "s3:GetObject"
        Resource = "${each.value.id}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.distribution.arn
          }
        }
      }
    ]
  })
}

resource "aws_cloudfront_function" "api-url-rewrite-function" {
  name    = "api-url-rewrite-function"
  runtime = "cloudfront-js-1.0"
  comment = "Rewrite API URLs routed to Nitric services"
  publish = true
  code    = templatefile("${path.module}/scripts/url-rewrite.js", {
    base_paths = join(",", [for k, v in var.nitric.origins : v.path])
  })
}

resource "aws_wafv2_web_acl" "cloudfront_waf" {
  count = var.waf_enabled ? 1 : 0

  name   = "${var.nitric.name}-cloudfront-waf"
  scope  = "CLOUDFRONT"
  region = "us-east-1"

  default_action {
    allow {}
  }

  # Rate limiting rule for DDoS protection
  dynamic "rule" {
    for_each = var.rate_limit_enabled ? [1] : []

    content {
      name     = "RateLimitRule"
      priority = 1

      action {
        block {}
      }

      statement {
        rate_based_statement {
          limit              = var.rate_limit_requests_per_5min
          aggregate_key_type = "IP"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "RateLimitRule"
        sampled_requests_enabled   = true
      }
    }
  }

  dynamic "rule" {
    for_each = var.waf_managed_rules

    content {
      name     = rule.value.name
      priority = rule.value.priority

      override_action {
        dynamic "none" {
          for_each = rule.value.override_action == "none" ? [1] : []
          content {}
        }
        dynamic "count" {
          for_each = rule.value.override_action == "count" ? [1] : []
          content {}
        }
      }

      statement {
        managed_rule_group_statement {
          name        = rule.value.name
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = rule.value.name
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.nitric.name}-cloudfront-waf"
    sampled_requests_enabled   = true
  }
}


# Extract parent domain by removing first subdomain
locals {
  domain_parts = split(".", var.custom_domain)
  parent_domain = join(".", slice(local.domain_parts, 1, length(local.domain_parts)))
}

# Lookup the parent hosted zone
data "aws_route53_zone" "parent" {
  count        = var.custom_domain != null ? 1 : 0
  name         = "${local.parent_domain}."
}

# Create Route53 A record for the custom domain
resource "aws_route53_record" "cloudfront_alias" {
  count   = var.custom_domain != null ? 1 : 0
  zone_id = data.aws_route53_zone.parent[0].zone_id
  name    = var.custom_domain
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.distribution.domain_name
    zone_id                = aws_cloudfront_distribution.distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

# Request ACM certificate for custom domain
resource "aws_acm_certificate" "cloudfront_cert" {
  count                     = var.custom_domain != null ? 1 : 0
  region                   = "us-east-1"  # CloudFront requires certificates in us-east-1
  domain_name              = var.custom_domain
  validation_method        = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# Create DNS validation records
resource "aws_route53_record" "cert_validation" {
  for_each = var.custom_domain != null ? {
    for dvo in aws_acm_certificate.cloudfront_cert[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      value  = dvo.resource_record_value
    }
  } : {}
  
  zone_id = data.aws_route53_zone.parent[0].zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.value]
  ttl     = 60
  
  allow_overwrite = true
}

# Wait for certificate validation to complete
resource "aws_acm_certificate_validation" "cloudfront_cert" {
  count                   = var.custom_domain != null ? 1 : 0
  region                  = "us-east-1"
  certificate_arn         = aws_acm_certificate.cloudfront_cert[0].arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

resource "aws_cloudfront_distribution" "distribution" {
  enabled = true
  web_acl_id = var.waf_enabled ? aws_wafv2_web_acl.cloudfront_waf[0].arn : null
  aliases = var.custom_domain != null ? [var.custom_domain] : []

  dynamic "origin" {
    for_each = local.non_vpc_origins

    content {
      # TODO: Only have services return their domain name instead? 
      domain_name = origin.value.domain_name
      origin_id = "${origin.key}"
      origin_access_control_id = contains(keys(origin.value.resources), "aws_lambda_function") ? aws_cloudfront_origin_access_control.lambda_oac[0].id : contains(keys(origin.value.resources), "aws_s3_bucket") ? aws_cloudfront_origin_access_control.s3_oac[0].id : null
      origin_path = origin.value.base_path

      dynamic "custom_origin_config" {
        for_each = !contains(keys(origin.value.resources), "aws_s3_bucket") ? [1] : []

        content {
          origin_read_timeout = 30
          origin_protocol_policy = "https-only"
          origin_ssl_protocols = ["TLSv1.2", "SSLv3"]
          http_port = 80
          https_port = 443
        }
      }
    }
  }

  dynamic "origin" {
    for_each = local.vpc_origins

    content {
      domain_name = origin.value.domain_name
      origin_id = "${origin.key}"
      vpc_origin_config {
        vpc_origin_id = aws_cloudfront_vpc_origin.vpc_origin[origin.key].id
      }
    }
  }

  dynamic "ordered_cache_behavior" {
    for_each = {
      for k, v in var.nitric.origins : k => v
      if v.path != "/"
    }

    content {
      path_pattern = "${ordered_cache_behavior.value.path}*"

      function_association {
        event_type = "viewer-request"
        function_arn = aws_cloudfront_function.api-url-rewrite-function.arn
      }

      allowed_methods = ["GET","HEAD","OPTIONS","PUT","POST","PATCH","DELETE"]
      cached_methods = ["GET","HEAD","OPTIONS"]
      target_origin_id = "${ordered_cache_behavior.key}"

      # Use AWS managed cache policy - UseOriginCacheHeaders
      # This policy honors the cache headers from the origin
      cache_policy_id = "83da9c7e-98b4-4e11-a168-04f0df8e2c65"
      
      # Use AWS managed origin request policy - AllViewer
      # This forwards all headers, query strings, and cookies to the origin
      origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3"

      viewer_protocol_policy = "https-only"
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "${keys(local.default_origin)[0]}"
    viewer_protocol_policy = "redirect-to-https"

    # Use AWS managed cache policy - UseOriginCacheHeaders
    # This policy honors the cache headers from the origin
    cache_policy_id = "83da9c7e-98b4-4e11-a168-04f0df8e2c65"
    
    # Use AWS managed origin request policy - AllViewer
    # This forwards all headers, query strings, and cookies to the origin
    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3"
  }

  restrictions {
    geo_restriction {
      restriction_type = var.geo_restriction_type
      locations        = var.geo_restriction_type != "none" ? var.geo_restriction_locations : []
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = var.custom_domain == null ? true : false
    acm_certificate_arn            = var.custom_domain != null ? aws_acm_certificate_validation.cloudfront_cert[0].certificate_arn : null
    ssl_support_method             = var.custom_domain != null ? "sni-only" : null
    minimum_protocol_version       = var.custom_domain != null ? "TLSv1.2_2021" : null
  }
}
