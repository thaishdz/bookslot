resource "aws_sns_topic" "booking_errors" {
  name = "bookslot-dev-booking-errors"
}

resource "aws_sns_topic_subscription" "booking_errors_email" {
  topic_arn = aws_sns_topic.booking_errors.arn
  protocol  = "http"
  endpoint  = var.alarm_email
}

resource "aws_cloudwatch_metric_alarm" "booking_errors" {
  alarm_name          = "bookslot-dev-booking-errors"
  alarm_description   = "Se dispara cuando la Lambda bookings acumula errores"

  # Qué métrica vigilar
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions = {
    FunctionName = aws_lambda_function.bookings.function_name
  }

  # Cómo evaluarla
  statistic           = "Sum"
  period              = 300          # 5 minutos en segundos
  evaluation_periods  = 1            # cuántos periodos evaluar
  threshold           = 1            # el umbral >= 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  # Qué hacer cuando salta
  alarm_actions       = [aws_sns_topic.booking_errors.arn]
  ok_actions    = [aws_sns_topic.booking_errors.arn] 
}