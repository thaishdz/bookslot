resource "aws_budgets_budget" "bookslot_monthly_v2" {
  name         = "bookslot-dev-monthly-v2"
  budget_type  = "COST"
  limit_amount = "10.0" # limite de mi cuenta de estudiante
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Aviso temprano: 50% del presupuesto (5$)
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alarm_email]
  }

  # Alerta: 80% del presupuesto (8$)
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alarm_email]
  }

  # Predictivo: se prevé superar el 100% (10$)
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alarm_email]
  }
}