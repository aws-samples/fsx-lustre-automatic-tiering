variable "region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "storage_capacity" {
  description = "1200 or a multiple of 2400"
  type        = number
  default     = 1200
}

variable "per_unit_storage_throughput" {
  description = "options: 125,250,500,1000"
  type        = number
  default     = 125
}

variable "sns_topic_email" {
  description = "The email to send alerts to when storage is low"
  type        = string
  default     = "example@example.com"
}

variable "alarm_storage_pct_threshold_for_sns_notifications" {
  description = "Threshold percentage for DRA storage alarm"
  type        = number
  default     = 0.15
}

variable "alarm_storage_pct_threshold_for_dra_emergency_release" {
  description = "Threshold percentage for emergency release of data from DRA directory"
  type        = number
  default     = 0.25
}

variable "duration_since_last_access_value" {
  description = "Duration since last access value"
  type        = number
  default     = 2
}
