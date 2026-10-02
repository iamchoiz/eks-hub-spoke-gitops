module "ecr" {
  source = "git::https://github.com/your-org/eks-hub-spoke-gitops.git//infra-terraform/modules/ecr?ref=main"

  repositories         = local.repositories
  image_tag_mutability = var.image_tag_mutability
  scan_on_push         = var.scan_on_push
}
