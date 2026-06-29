
resource "aws_apigatewayv2_integration" "bookings" {
  api_id           = aws_apigatewayv2_api.main.id
  integration_type = "AWS_PROXY"

  description               = "Lambda Bookings"
  integration_uri           = aws_lambda_function.bookings.invoke_arn
  payload_format_version    = "2.0"
}

resource "aws_apigatewayv2_route" "bookings" {
  for_each  = toset(["POST /bookings", "DELETE /bookings"])
  api_id    = aws_apigatewayv2_api.main.id
  route_key = each.value
  target    = "integrations/${aws_apigatewayv2_integration.bookings.id}"

  authorization_type = "JWT"                                   
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "bookings_lambda_permission" {
  statement_id  = "AllowBookingsAPIInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.bookings.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}