# Learner Lab only allows us-east-1 (AGENTS §4).

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = local.tags
  }
}

# Talks to the cluster created in this stack. The token comes from the AWS CLI with the
# current lab credentials, so it keeps working after `make creds`.
provider "helm" {
  kubernetes = {
    host                   = aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.this.certificate_authority[0].data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.this.name, "--region", "us-east-1"]
    }
  }
}
