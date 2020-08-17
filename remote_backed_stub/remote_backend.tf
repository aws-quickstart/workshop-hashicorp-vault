terraform {
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "aws-devops-workshop-replace"
    workspaces {
      name = "aws-devops-workshop"
    }
  }
}
