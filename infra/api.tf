
// Paso 1. Definir API Gateway
resource "aws_apigatewayv2_api" "main" {
  name          = "bookslot-dev-api"
  protocol_type = "HTTP"
}

// Paso 4. Desplegar API GW
resource "aws_apigatewayv2_stage" "dev" {
  api_id = aws_apigatewayv2_api.main.id
  name   = "dev"
  auto_deploy = true
}