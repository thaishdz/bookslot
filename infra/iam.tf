/*
  Así crearíamos un rol propio para esta Lambda,
  con permisos acotados solo a las operaciones que usan (PutItem, Query, Scan)
  y solo sobre la tabla bookings.

  NO se puede aplicar en la cuenta de estudiante el rol StudentLabAccess dado que
  no tiene permiso para iam:CreateRole. Por eso reutilizamos el rol existente
  studentLambdaExecutionRole (data source abajo).

  Se deja documentado para demostrar como se haria en un entorno "real".

resource "aws_iam_role" "resources_lambda" { # existe este rol
  name = "bookslot-dev-resources-lambda-role"

  assume_role_policy = jsonencode({ # y este servicio (Lambda) puede ponérselo ---> trust policy
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "resources_lambda_dynamodb" {
  name = "bookslot-dev-resources-dynamodb-policy"
  role = aws_iam_role.resources_lambda.id   # adjunta esta política al rol de arriba

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.bookings.arn   # solo  tabla, por su ARN
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}
*/

data "aws_iam_role" "lambda_exec" {
  name = "studentLambdaExecutionRole"
}