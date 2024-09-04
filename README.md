# browserless-as-lambda

Use browserless as a lambda function to convert html to pdf.

## Deploy

```bash
npm install
zip -r function.zip .
```

## Configure the Lambda function
1. Increase the timeout (PDF generation might take some time)
2. Increase the memory allocation if needed (1GB is the minimum)
3. Add necessary permissions for CloudWatch Logs

## Update Lambda Function Environment Variable

```bash
API_KEY=your-browserless-api-key
S3_BUCKET_NAME=your-s3-bucket-name
```