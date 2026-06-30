// Paso 2. Definir la integración API GW -> Lambda
resource "aws_apigatewayv2_integration" "resources" {
  api_id           = aws_apigatewayv2_api.main.id
  integration_type = "AWS_PROXY"

  description               = "Lambda Resources"
  integration_uri           = aws_lambda_function.resources.invoke_arn
  payload_format_version    = "2.0"
}

// Paso 3. Montar los endpoints de LECTURA (rutas públicas)
resource "aws_apigatewayv2_route" "resources_read" {
  for_each = toset(["GET /resources", "GET /resources/{id}/slots"])

  api_id    = aws_apigatewayv2_api.main.id
  route_key = each.value

  target = "integrations/${aws_apigatewayv2_integration.resources.id}"
}

// Paso 3. Montar los endpoints de ESCRITURA (protegidos, solo admins)
resource "aws_apigatewayv2_route" "resources_write" {
  for_each = toset(["POST /resources", "POST /resources/{id}/slots"])

  api_id    = aws_apigatewayv2_api.main.id
  route_key = each.value

  target = "integrations/${aws_apigatewayv2_integration.resources.id}"

  authorization_type = "JWT"
  authorizer_id       = aws_apigatewayv2_authorizer.cognito.id
}


// Paso 5. Darle permisos a la API GW para invocar la lambda resources
resource "aws_lambda_permission" "resources_lambda_permission" {
  statement_id  = "AllowResourcesAPIInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.resources.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.main.execution_arn}/*/*" // /*/* desde cualquier stage Y método/ruta
}