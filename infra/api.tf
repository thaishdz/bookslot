
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

// Valida los tokens de Cognito antes de que la petición llegue a la Lambda
resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.main.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "bookslot-cognito-authorizer"

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.main.id]
    issuer   = "https://cognito-idp.eu-west-1.amazonaws.com/${aws_cognito_user_pool.main.id}"
  }
}