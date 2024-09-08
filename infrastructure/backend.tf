terraform {
  backend "s3" {
    bucket = "infrastructure-terraform-ryan"
    region = "us-east-1"
  }
}
