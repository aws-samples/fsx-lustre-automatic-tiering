# ----------------------------------------------------------------------#
#                         Terraform Provider                            #
# ----------------------------------------------------------------------#
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

provider "aws" {
  region = var.region
}


# ----------------------------------------------------------------------#
#                               Locals                                  #
# ----------------------------------------------------------------------#
locals {
  dra_file_system_path = "/dra"
  dra_s3_bucket_prefix = "fsxl-dra"
  tags = {
    env    = var.environment
    region = var.region
  }
}

# ----------------------------------------------------------------------#
#                               FSXL VPC                                #
# ----------------------------------------------------------------------#
# Fetch the available availability zones in the current region
data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  # source             = "terraform-aws-modules/vpc/aws"
  source                 = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc.git?ref=v5.13.0"
  name                   = "demo-vpc"
  cidr                   = "10.0.0.0/16"
  azs                    = data.aws_availability_zones.available.names
  private_subnets        = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets         = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false
  tags                   = local.tags
}


# ----------------------------------------------------------------------#
#                         FSxL Security Group                           #
# ----------------------------------------------------------------------#
# Create Security Group for FSxL
resource "aws_security_group" "fsxl_sg" {
  name        = "demo-fsxl-sg-${var.region}"
  description = "FSxL Allow inbound traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Self Security"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    description      = "Allow all out bound ports to all ipaddress"
    ipv6_cidr_blocks = ["::/0"]
  }
  tags = local.tags
}

# ----------------------------------------------------------------------#
#                          FSxL File System                             #
# ----------------------------------------------------------------------#

resource "aws_fsx_lustre_file_system" "demo_file_system" {
  deployment_type             = "PERSISTENT_2"
  storage_capacity            = var.storage_capacity
  per_unit_storage_throughput = var.per_unit_storage_throughput
  subnet_ids                  = [module.vpc.private_subnets[0]]
  security_group_ids          = [aws_security_group.fsxl_sg.id]
  tags                        = local.tags
}


# ----------------------------------------------------------------------#
#                     FSxL DRA Configuration                            #
# ----------------------------------------------------------------------#

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "dra_bucket" {
  bucket        = "demo-dra-${data.aws_caller_identity.current.account_id}-${var.region}"
  force_destroy = true
  tags          = local.tags
}
# public access block
resource "aws_s3_bucket_public_access_block" "public_block" {
  bucket                  = aws_s3_bucket.dra_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
# Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "encryption" {
  bucket = aws_s3_bucket.dra_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
# S3 bucket versioning eanble
resource "aws_s3_bucket_versioning" "dra_bucket_versioning" {
  bucket = aws_s3_bucket.dra_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}
# S3 bucket logging
resource "aws_s3_bucket_logging" "dra_bucket_logging" {
  bucket = aws_s3_bucket.dra_bucket.id

  target_bucket = aws_s3_bucket.dra_bucket.id
  target_prefix = local.dra_s3_bucket_prefix
}

# Data Repository Association
resource "aws_fsx_data_repository_association" "fsxl_dra" {
  file_system_id                   = aws_fsx_lustre_file_system.demo_file_system.id
  data_repository_path             = "s3://${aws_s3_bucket.dra_bucket.id}/${local.dra_s3_bucket_prefix}/"
  file_system_path                 = local.dra_file_system_path
  batch_import_meta_data_on_create = true
  tags                             = local.tags
  s3 {
    auto_export_policy {
      events = ["NEW", "CHANGED", "DELETED"]
    }

    auto_import_policy {
      events = ["NEW", "CHANGED", "DELETED"]
    }
  }
}




#----------------------------------------------------------------------#
#            Lambda Function for FSxL Emergency Release                #
#----------------------------------------------------------------------#

# Lambda function to trigger dra
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "../lambda/index.py"
  output_path = "../lambda/index.zip"
}
# Lambda function
resource "aws_lambda_function" "trigger_fsxl_dra_release" {
  function_name    = "fsxl_dra_release_lambda"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  role             = aws_iam_role.aws_lambda_role.arn
  vpc_config {
    subnet_ids         = module.vpc.private_subnets
    security_group_ids = [aws_security_group.fsxl_sg.id]
  }
  handler                 = "index.lambda_handler"
  runtime                 = "python3.12"
  timeout                 = 30
  code_signing_config_arn = aws_lambda_code_signing_config.dra_lambda.arn
  tags                    = local.tags
  environment {
    variables = {
      days_since_last_access = 0
      dra_file_system_path   = "/dra"
    }
  }
}

# Lambda Code Signining Config
resource "aws_lambda_code_signing_config" "dra_lambda" {
  allowed_publishers {
    signing_profile_version_arns = ["arn:aws:signer:${var.region}:${data.aws_caller_identity.current.account_id}:/signing-profile/fsxl_dra_release_lambda"]
  }
  policies {
    untrusted_artifact_on_deployment = "Warn"
  }
}

# Lambda permission to allow invokes from cloudwatch alarms
resource "aws_lambda_permission" "allow_cloudwatch_alarms" {
  statement_id  = "AllowExecutionFromCloudWatchAlarms"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.trigger_fsxl_dra_release.function_name
  principal     = "lambda.alarms.cloudwatch.amazonaws.com"
  source_arn    = "arn:aws:cloudwatch:${var.region}:${data.aws_caller_identity.current.account_id}:alarm:*"
}
# Lambda Cloudwatch LogGroup
resource "aws_cloudwatch_log_group" "trigger_fsxl_dra_release" {
  name              = format("/aws/lambda/%s", aws_lambda_function.trigger_fsxl_dra_release.function_name)
  retention_in_days = 365
  tags              = local.tags
}

#----------------------------------------------------------------------#
#                   Lambda IAM Role and Policies                       #
#----------------------------------------------------------------------#
# IAM policy for lambda to assume role
data "aws_iam_policy_document" "lambda_assume_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}
# IAM policy for lambda to access FSxL
data "aws_iam_policy_document" "fsx_access" {
  statement {
    actions = [
      "fsx:CreateDataRepositoryTask",
      "fsx:DescribeDataRepositoryAssociations"
    ]
    resources = ["*"]
  }
  statement {
    actions   = ["ec2:CreateNetworkInterface", "ec2:DescribeNetworkInterfaces", "ec2:DeleteNetworkInterface"]
    resources = ["*"]
  }

}
# IAM role for lambda
resource "aws_iam_role" "aws_lambda_role" {
  name               = "${var.region}-lambda-fsxl-dra-release-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_policy.json
  tags               = local.tags
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
    "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
  ]

  inline_policy {
    name   = "fsx-create-dra-task"
    policy = data.aws_iam_policy_document.fsx_access.json
  }
}

# ----------------------------------------------------------------------#
#             Eventbridge Schedule for FSxL Release                     #
# ----------------------------------------------------------------------#
data "aws_iam_policy_document" "eventbridge_scheduler_trust_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "eventbridge_scheduler_role" {
  name               = "fsxl-dra-eventbridge-scheduler-role-${var.region}"
  assume_role_policy = data.aws_iam_policy_document.eventbridge_scheduler_trust_policy.json
  tags               = local.tags
  inline_policy {
    name = "create_data_repository_task"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action   = ["fsx:CreateDataRepositoryTask"]
          Effect   = "Allow"
          Resource = "*"
        },
      ]
    })
  }
}
# Eventbridge schedule to regularly run a data repository release task
resource "aws_scheduler_schedule" "fsxl_schedule" {
  name                = "fsxl_release_schedule_${aws_fsx_lustre_file_system.demo_file_system.id}"
  schedule_expression = "rate(1 days)"
  # kms_key_arn         = aws_kms_key.custom_sns_key.arn
  target {
    arn      = "arn:aws:scheduler:::aws-sdk:fsx:createDataRepositoryTask"
    role_arn = aws_iam_role.eventbridge_scheduler_role.arn
    input = jsonencode({
      FileSystemId = aws_fsx_lustre_file_system.demo_file_system.id
      Type         = "RELEASE_DATA_FROM_FILESYSTEM"
      Paths        = [local.dra_file_system_path]
      ReleaseConfiguration = {
        DurationSinceLastAccess = {
          Unit  = "DAYS"
          Value = var.duration_since_last_access_value
        }
      }
      Report = {
        Enabled = true
        Path    = "s3://${aws_s3_bucket.dra_bucket.id}/${local.dra_s3_bucket_prefix}/release-task-reports"
        Format  = "REPORT_CSV_20191124"
        Scope   = "FAILED_FILES_ONLY"
      }
    })
  }
  flexible_time_window {
    mode = "OFF"
  }
}

# ----------------------------------------------------------------------#
#                     FSxL Storage Monitoring                           #
# ----------------------------------------------------------------------#

# Cloudwatch alarm to trigger release tasks at 15% remaining capacity or below (for DRA-enabled FSxLs) 
resource "aws_cloudwatch_metric_alarm" "fsxl_available_storage_alarm" {
  alarm_name                = "fsxl-low-available-storage"
  comparison_operator       = "LessThanOrEqualToThreshold"
  evaluation_periods        = 10
  metric_name               = "FreeDataStorageCapacity"
  namespace                 = "AWS/FSx"
  period                    = 60
  statistic                 = "Sum"
  threshold                 = var.storage_capacity * 1e9 * var.alarm_storage_pct_threshold_for_sns_notifications
  alarm_description         = "This alarm triggers a DRA release when available storage capacity on the associated FSxL (${aws_fsx_lustre_file_system.demo_file_system.id} / ${aws_fsx_lustre_file_system.demo_file_system.id}) is <= ${tonumber(format("%.2f", var.alarm_storage_pct_threshold_for_sns_notifications * 100))}%"
  insufficient_data_actions = []
  alarm_actions             = [aws_lambda_function.trigger_fsxl_dra_release.arn]
  tags                      = local.tags
  dimensions = {
    FileSystemId = aws_fsx_lustre_file_system.demo_file_system.id
  }
}

# Cloudwatch alarms to trigger SNS notifications at low remaining storage capacity (for all FSxLs)
resource "aws_cloudwatch_metric_alarm" "fsxl_available_storage_alarm_for_sns" {
  alarm_name                = "fsxl-notify-low-available-storage (${aws_fsx_lustre_file_system.demo_file_system.id})"
  comparison_operator       = "LessThanOrEqualToThreshold"
  evaluation_periods        = 10
  metric_name               = "FreeDataStorageCapacity"
  namespace                 = "AWS/FSx"
  period                    = 60
  statistic                 = "Sum"
  threshold                 = var.storage_capacity * 1e9 * var.alarm_storage_pct_threshold_for_dra_emergency_release
  alarm_description         = "This alarm sends SNS notifications when available storage capacity on the associated FSxl (${aws_fsx_lustre_file_system.demo_file_system.id} / ${aws_fsx_lustre_file_system.demo_file_system.id}) is <= ${tonumber(format("%.2f", var.alarm_storage_pct_threshold_for_dra_emergency_release * 100))}%"
  insufficient_data_actions = []
  alarm_actions             = [aws_sns_topic.fsxl_storage_notification.arn]
  tags                      = local.tags
  dimensions = {
    FileSystemId = aws_fsx_lustre_file_system.demo_file_system.id
  }
}



#----------------------------------------------------------------------#
#                     SNS Topic Notifications                          #
#----------------------------------------------------------------------#
# SNS topic for FSxL storage notifications (used by CW alarms)
resource "aws_sns_topic" "fsxl_storage_notification" {
  name              = "fsxl-dra-storage-notification"
  kms_master_key_id = aws_kms_key.custom_sns_key.key_id
  tags              = local.tags
}

# Add SNS topic susbscriptions
resource "aws_sns_topic_subscription" "topic_email_subscription" {
  topic_arn = aws_sns_topic.fsxl_storage_notification.arn
  protocol  = "email"
  endpoint  = var.sns_topic_email //FEEDBACK: ADD VARIABLE
}

# KMS key for SNS
resource "aws_kms_key" "custom_sns_key" {
  description         = "KMS key for SNS topic"
  enable_key_rotation = true
  policy              = <<EOP
  {
        "Id": "sns-key-for-cloudwatch",
        "Version": "2012-10-17",
        "Statement": [
          {
              "Sid": "Allow_CloudWatch_access",
              "Effect": "Allow",
              "Principal": {
                  "Service":[
                      "cloudwatch.amazonaws.com"
                  ]
              },
              "Action": [
                  "kms:Decrypt","kms:GenerateDataKey*"
              ],
              "Resource": "*"
          },
          {
            "Sid": "Enable IAM User Permissions",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
            },
            "Action": "kms:*",
            "Resource": "*"
        }
        ]
    }

  EOP
}
# KMS alias for SNS
resource "aws_kms_alias" "key_alias" {
  name          = "alias/custom-sns-key"
  target_key_id = aws_kms_key.custom_sns_key.key_id
}