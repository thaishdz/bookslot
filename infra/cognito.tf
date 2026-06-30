resource "aws_cognito_user_pool" "main" {
  name = "bookslot-dev-users"

  # El email será el atributo con el que los usuarios hacen login
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  # Política de contraseñas
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = true
  }

  schema {
    name                = "dni"
    attribute_data_type = "String"
    mutable             = false 
    required            = false

    string_attribute_constraints {
      min_length = 9
      max_length = 9
    }
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "bookslot-dev-client"
  user_pool_id = aws_cognito_user_pool.main.id

  # Flujos de autenticación permitidos
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",   # login con usuario+contraseña
    "ALLOW_REFRESH_TOKEN_AUTH"    # renovar el token sin re-login
  ]

  # Para apps públicas/sin backend confidencial
  generate_secret = false
}

resource "aws_cognito_user_group" "admins" {
  name         = "admins"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "Usuarios con permiso para crear recursos y slots"
}