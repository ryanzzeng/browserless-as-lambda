provider "aws" {
  region = var.aws_region
}

# S3 definition
resource "aws_s3_bucket" "lambda_bucket" {
  bucket = "browserless-lambda-bucket"
}

resource "aws_s3_bucket_ownership_controls" "lambda_bucket" {
  bucket = aws_s3_bucket.lambda_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "lambda_bucket" {
  depends_on = [aws_s3_bucket_ownership_controls.lambda_bucket]

  bucket = aws_s3_bucket.lambda_bucket.id
  acl    = "private"
}

# Source code definition and upload to s3 bucket
data "archive_file" "lambda_pdf_generate" {
  type = "zip"
  source_dir = "${path.module}/../src"
  output_path = "${path.module}/../pdf-generate.zip"
}

resource "aws_s3_object" "lambda_pdf_generate" {
  bucket = aws_s3_bucket.lambda_bucket.id

  key    = "pdf-generate.zip"
  source = data.archive_file.lambda_pdf_generate.output_path

  etag = filemd5(data.archive_file.lambda_pdf_generate.output_path)
}

# Lambda function definition
resource "aws_lambda_function" "pdf_generate" {
  function_name = "PdfGenerate"

  s3_bucket = aws_s3_bucket.lambda_bucket.id
  s3_key    = aws_s3_object.lambda_pdf_generate.key

  runtime = "nodejs20.x"
  handler = "index.handler"

  source_code_hash = data.archive_file.lambda_pdf_generate.output_base64sha256

  role = aws_iam_role.lambda_exec.arn

  # Defining environment variables
  environment {
    variables = {
      S3_BUCKET_NAME = aws_s3_bucket.lambda_bucket.bucket
      API_KEY = "0f6e764a-b025-4294-8519-246ec84a4a20"
    }
  }

  memory_size = "1024"
  timeout = "30"
}

resource "aws_cloudwatch_log_group" "pdf_generate" {
  name = "/aws/lambda/${aws_lambda_function.pdf_generate.function_name}"

  retention_in_days = 30
}

resource "aws_iam_role" "lambda_exec" {
  name = "serverless_lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Sid    = ""
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "s3_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

// API Gateway
resource "aws_apigatewayv2_api" "lambda" {
  name          = "serverless_lambda_gw"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "lambda" {
  api_id = aws_apigatewayv2_api.lambda.id

  name        = "serverless_lambda_stage"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn

    format = jsonencode({
      requestId               = "$context.requestId"
      sourceIp                = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      protocol                = "$context.protocol"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
      }
    )
  }
}

resource "aws_apigatewayv2_integration" "pdf_generate" {
  api_id = aws_apigatewayv2_api.lambda.id

  integration_uri    = aws_lambda_function.pdf_generate.invoke_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "pdf_generate" {
  api_id = aws_apigatewayv2_api.lambda.id

  route_key = "POST /pdf"
  target    = "integrations/${aws_apigatewayv2_integration.pdf_generate.id}"
}

resource "aws_cloudwatch_log_group" "api_gw" {
  name = "/aws/api_gw/${aws_apigatewayv2_api.lambda.name}"

  retention_in_days = 30
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pdf_generate.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.lambda.execution_arn}/*/*"
}
