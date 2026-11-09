terraform {
  backend "s3" {
    bucket         = "petclinic-terraform-state-746859878803"
    key            = "petclinic/global/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "petclinic-terraform-locks"
    encrypt        = true
  }
}
