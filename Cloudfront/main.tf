
resource "aws_s3_bucket" "site_origin" {
  bucket = "host-website-mf37"
}
resource "aws_s3_bucket_public_access_block" "site_origin" {
  bucket                  = aws_s3_bucket.site_origin.bucket
  block_public_acls       = false //prevent the creation or modification of public ACLs on objects within the bucket
  block_public_policy     = false //Whether Amazon S3 should block public bucket policies for this bucket
  ignore_public_acls      = false //Whether Amazon S3 should ignore public ACLs for this bucket
  restrict_public_buckets = false // Whether Amazon S3 should restrict public bucket policies for this bucket.
}
resource "aws_s3_bucket_server_side_encryption_configuration" "site_origin" {
  bucket = aws_s3_bucket.site_origin.bucket
  rule {
    apply_server_side_encryption_by_default { // protect data at rest
      sse_algorithm = "AES256"
    }
  }
}
resource "aws_s3_bucket_versioning" "site_origin" {
  bucket = aws_s3_bucket.site_origin.bucket
  versioning_configuration { // prevent accidental deletion
    status = "Enabled"
  }
}
resource "aws_s3_object" "content" { // create object after creating bucket
  depends_on = [
    aws_s3_bucket.site_origin
  ]
  bucket                 = aws_s3_bucket.site_origin.bucket
  key                    = "index.html"
  source                 = "index.html"
  server_side_encryption = "AES256"
  content_type           = "text/html" // specify content type
}

data "aws_acm_certificate" "amazon_issued" {
  domain      = var.subdomain_name
  types       = ["AMAZON_ISSUED"]
  most_recent = true
}

resource "aws_cloudfront_origin_access_control" "site_access" {
  name                              = "security_pillar100_cf_s3_oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always" // refers to process of generating signed urls to control access to content
  signing_protocol                  = "sigv4"  // procedures that govern the use/generation of signed urls and cookies/ specifies format and content of access policy/algorithms for signing
}
resource "aws_cloudfront_distribution" "site_access" {
  depends_on = [ // resource depends on the creation of your s3 bucket
    aws_s3_bucket.site_origin,
    aws_cloudfront_origin_access_control.site_access,
  ]
  enabled             = true         // states distribution is enabled upon creation 
  default_root_object = "index.html" // tells distribution which page to load first 

  default_cache_behavior { // describes how we want cloudfront to fetch objects from s3
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = aws_s3_bucket.site_origin.id
    viewer_protocol_policy = "redirect-to-https" //redirect http traffic to https
    min_ttl                = 10
    default_ttl            = 30
    max_ttl                = 60

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }
  aliases = [var.domain_name, var.subdomain_name] //missing
  origin {
    domain_name              = aws_s3_bucket.site_origin.bucket_regional_domain_name
    origin_id                = aws_s3_bucket.site_origin.id
    origin_access_control_id = aws_cloudfront_origin_access_control.site_access.id
  }
  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US", "CA"]
    }
  }
  viewer_certificate {
    acm_certificate_arn = data.aws_acm_certificate.amazon_issued.id
    ssl_support_method  = "sni-only"
  }
  tags = {
    Description = "host personal website"
  }
}

resource "aws_s3_bucket_policy" "site_origin" {
  bucket = aws_s3_bucket.site_origin.id
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [{
      "Sid" : "PublicReadGetObject",
      "Effect" : "Allow",
      "Principal" : {
          "Service" : "cloudfront.amazonaws.com"
        },
      "Action" : "s3:GetObject",
      "Resource" : "arn:aws:s3:::${aws_s3_bucket.site_origin.id}/*"
    }]
  })
}

data "aws_route53_zone" "hosted_zone" {
  name         = var.domain_name
  private_zone = false
}
resource "aws_route53_record" "primary_alias" {
  zone_id = data.aws_route53_zone.hosted_zone.zone_id
  name    = "www.${data.aws_route53_zone.hosted_zone.name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.site_access.domain_name    // refers to distribution domain name after new cf created
    zone_id                = aws_cloudfront_distribution.site_access.hosted_zone_id // Fixed value for CloudFront distribution
    evaluate_target_health = true
  }
  failover_routing_policy {
    type = "PRIMARY"
  }
  set_identifier = "primary"
  health_check_id = aws_route53_health_check.primary.id
}
resource "aws_route53_record" "secondary_alias" {
  zone_id = data.aws_route53_zone.hosted_zone.zone_id
  name    = "www.${data.aws_route53_zone.hosted_zone.name}"
  type    = "A"
  
  alias {
    name                   = aws_cloudfront_distribution.site_access.domain_name    // refers to distribution domain name after new cf created
    zone_id                = aws_cloudfront_distribution.site_access.hosted_zone_id // Fixed value for CloudFront distribution
    evaluate_target_health = true
  }
  failover_routing_policy {
    type = "SECONDARY"
  }
  set_identifier = "secondary"
  health_check_id = aws_route53_health_check.secondary.id
}

resource "aws_route53_health_check" "primary" {
  fqdn              = "www.${data.aws_route53_zone.hosted_zone.name}"
  port              = 443
  type              = "HTTPS"
  request_interval  = 30
  failure_threshold = 3
  tags = {
    Name = "primary_health_check"
  }
}

resource "aws_route53_health_check" "secondary" {
  fqdn              = "www.${data.aws_route53_zone.hosted_zone.name}"
  port              = 443
  type              = "HTTPS"
  request_interval  = 30
  failure_threshold = 3
  tags = {
    Name = "secondary_health_check"
  }
}



# resource "aws_route53_health_check" "health" {
#   fqdn              = "www.fejzic37.com"
#   port              = 80
#   type              = "HTTP"
#   resource_path     = "index.html"
#   failure_threshold = "5"
#   request_interval  = "30"

#   tags = {
#     Name = "tf-test-health-check"
#   }
# }

/*


resource "aws_s3_bucket_policy" "site_origin" {
  depends_on = [
    data.aws_iam_policy_document.site_origin
  ]
  bucket = aws_s3_bucket.site_origin.id
  policy = data.aws_iam_policy_document.site_origin.json
}

data "aws_iam_policy_document" "site_origin" {
  depends_on = [
    aws_cloudfront_distribution.site_access,
    aws_s3_bucket.site_origin
  ]
  statement {
    sid     = "s3_cloudfront_static_website"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    resources = ["arn:aws:s3:::${aws_s3_bucket.site_origin.bucket}/*"]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceARN"
      values   = [aws_cloudfront_distribution.site_access.id]
    }
  }
}




resource "aws_s3_bucket_policy" "site_origin" {
  bucket = aws_s3_bucket.site_origin.id
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [{
      "Sid" : "PublicReadGetObject",
      "Effect" : "Allow",
      "Principal" : {
          "Service" : "cloudfront.amazonaws.com"
        },
      "Action" : "s3:GetObject",
      "Resource" : "arn:aws:s3:::${aws_s3_bucket.site_origin.id}/*"
    }]
  })
}


*/