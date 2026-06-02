provider "aws" {
  region = "eu-west-1"

  default_tags {
    tags = {
      Project     = "bookslot"
      Environment = "dev"
      Owner       = "Thais"
    }
  }
}