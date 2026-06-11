# Con este código, Terraform buscará y encapsulará la lambda (handler.py) en un .zip

data "archive_file" "resources_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/../services/resources"
  output_path = "${path.module}/../services/resources.zip"
}


resource "aws_lambda_function" "resources" {
  function_name = "bookslot-dev-resources"
  role          = data.aws_iam_role.lambda_exec.arn

  filename         = data.archive_file.resources_lambda.output_path
  source_code_hash = data.archive_file.resources_lambda.output_base64sha256

  handler = "handler.lambda_handler" # archivo.function
  runtime = "python3.13"
}