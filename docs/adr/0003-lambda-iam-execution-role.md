# ADR-0003: IAM Role de ejecución de las Lambdas

## Contexto

**Toda función Lambda necesita un rol de IAM para ejecutarse**.   
El rol cumple dos funciones: define quién puede asumir la identidad de la Lambda (trust policy) y qué permisos tiene sobre otros servicios de AWS (DynamoDB, CloudWatch Logs, etc).

El proyecto exige aplicar el principio de **mínimo privilegio**: cada   
componente debe tener únicamente los permisos estrictamente necesarios para su función, ni uno más. Para la Lambda de `resources`, esto significa un rol que solo pueda hacer las operaciones que especifiquemos en el código de la misma, y solo sobre la tabla que diseñamos en DynamoDB.

La decisión que documenta este ADR será la de cómo resolver el rol de ejecución de las Lambdas dentro de las restricciones de una cuenta de estudiante de AWS, que no permite crear roles ni políticas propias.

## Decisión

Ante la imposibilidad de crear un rol propio, decidí reutilizar un rol que la cuenta de estudiante ya trae preconfigurado (`tudentLambdaExecutionRole`).

Para usarlo empleé el `data`(en lugar de un `resource`) porque no quiero crear el rol, sino referenciar uno que ya existe. Un `data` le dice a Terraform "busca este recurso preexistente y dame sus datos", mientras que un `resource` lo crearía desde cero.

```py
data "aws_iam_role" "lambda_exec" {
  name = "studentLambdaExecutionRole"
}
```

Una vez definido lo anterior, en el archivo `infra/lambdas.tf`, la Lambda usará el ARN del rol mediante:  
```py
resource "aws_lambda_function" "resources" {
  function_name = "bookslot-dev-resources"
  role          = data.aws_iam_role.lambda_exec.arn

(...)
```

## Trade-offs

El principal trade-off que he visto es a nivel de **IAM Roles**, ya que al   trabajar dentro de una cuenta de estudiante con roles predefinidos, no   puedo acotar los permisos del rol a lo que mi Lambda realmente necesita.

Investigué las políticas del rol `studentLambdaExecutionRole` y la política `StudentLambdaDynamoDBAccess` asociadas a mi cuenta y esta permite realizar las siguientes *11 operaciones* sobre *DynamoDB*:

- `GetItem`  
- `PutItem`  
- `UpdateItem`  
- `DeleteItem`  
- `BatchGetItem`  
- `BatchWriteItem`  
- `Query`  
- `Scan`  
- `DescribeTable`  
- `ListTables`  
- `ConditionCheckItem`

Todas ellas sobre `Resource: "*"` (todas las tablas de la cuenta). Además,   el rol incluye permisos de SQS, SNS y X-Ray que esta Lambda `resources` en particular, tampoco usará.

Esta Lambda, en este MVP, tan solo necesitaría 3 operaciones que son las que hemos especificado en el `/services/resources/handler.py`:

- `PutItem`  
- `Query`  
- `Scan`

sobre la única tabla que hemos definido `bookslot-dev-bookings`.

Si bien es cierto que, en un futuro se podrían añadir las operaciones de eliminación y modificación de un recurso, en estos momentos exceden el alcance planteado inicialmente para el MVP.

Debido a estas razones, se entiende que **se incumple el requisito de mínimo privilegio** haciendo posible asumir un riesgo. Por ejemplo, si la Lambda se viese comprometida por un atacante, podría borrar o modificar datos de cualquier tabla de la cuenta (recordemos `Resource: "*"`). Además, al ser un rol compartido por todas   las Lambdas de estudiante, se pierde el aislamiento entre funciones.

Conviene recalcar que *no todos los permisos del rol de estudiante son problemáticos*. Ya que según vimos, también se nos otorgan permisos de **CloudWatch Logs**:

- `logs:CreateLogGroup`
- `logs:CreateLogStream`
- `logs:PutLogEvents`

mediante la política `AWSLambdaBasicExecutionRole`. Estos permisos no solo son necesarios para registrar y debugar las acciones que realiza nuestra Lambda, sino que además cumplen con el requisito de observabilidad del proyecto (*logs centralizados en CloudWatch*).

# Solución ideal

En un entorno no académico, la solución ideal sería **crear un IAM Role exclusivo para cada Lambda**, acotado a:

- Las operaciones que esa Lambda realizará
- `dynamodb:PutItem`  
- `dynamodb:Query`
- `dynamodb:Scan`, más los permisos de logs de CloudWatch, anteriormente descritos.

- El recurso concreto sobre el que opera. 
  - En lugar de `Resource: "*"`,   el ARN de la única tabla del proyecto (`bookslot-dev-bookings`).

**Esto garantiza no solo el mínimo privilegio sobre cada Lambda** que haría lo estrictamente necesario sino que se mantendría el aislamiento entre ellas, de modo que, si una se viera comprometida, el riesgo quedaría acotado a sus permisos y no se extendería al resto.

Este rol ideal, junto con su política de mínimo privilegio, quedó  
comentado en `/infra/iam.tf`como referencia de cómo se implementaría en un entorno con permisos para crear roles y políticas:

```py
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
```