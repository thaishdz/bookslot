variable "alarm_email" {
  description = "Email destino de las alarmas de CloudWatch y budgets"
  type        = string
  sensitive   = true
}