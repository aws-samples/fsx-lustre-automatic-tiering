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
  type    = string
  default = "example@example.com"
}