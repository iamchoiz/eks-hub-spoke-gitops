region                      = "ap-northeast-2"
account_id                  = "111111111111"
resource_prefix             = "demo"
observability_ssm_namespace = "observability"
vpc_ssm_namespace           = "vpc"
default_tags = {
  Project    = "demo"
  Env        = "hub"
  Owner      = "admin"
  ManagedBy  = "terraform"
  CostCenter = "platform"
}
cluster_name_base            = "hub-01"
kubernetes_version           = "1.35"
endpoint_public_access_cidrs = ["203.0.113.10/32", "203.0.113.20/32"]
cluster_log_types            = []
addon_versions = {
  coredns                = "v1.13.2-eksbuild.31"
  kube_proxy             = "v1.35.3-eksbuild.29"
  vpc_cni                = "v1.22.4-eksbuild.3"
  eks_pod_identity_agent = "v1.3.10-eksbuild.3"
  aws_ebs_csi_driver     = "v1.66.0-eksbuild.1"
}
access_entries = {
  admin = {
    principal  = "user/admin"
    policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
    scope_type = "cluster"
    namespaces = []
  }
}
system_scaling            = { min = 1, max = 2, desired = 1 }
system_instance_types     = ["t4g.medium", "t4g.large"]
system_kubernetes_version = "1.35"
system_release_version    = "1.66.0-1ad6b4a4" # 10/1 in-place 때 콘솔에서 1.66.0 으로 롤링됨 — tfvars 를 실버전에 맞춤 (1.65.0 으로 두면 apply 가 다운그레이드 롤링을 건다)
system_capacity_type      = "ON_DEMAND"
argocd_namespace          = "argocd"
argocd_service_accounts = [
  "argocd-application-controller",
  "argocd-server",
]
spoke_role_name_pattern     = "*-argocd-spoke"
loki_namespace              = "monitoring"
loki_service_account        = "loki"
loki_role_suffix            = "loki"
loki_policy_key             = "loki-policy-arn"
argocd_mgmt_role_suffix     = "argocd-mgmt"
argocd_mgmt_policy_name     = "assume-spoke-roles"
loki_gateway_port           = 8080
loki_gateway_sg_protocol    = "tcp"
loki_gateway_sg_description = "spoke fluent-bit to hub loki-gateway (E1)"

partition = "aws"

cluster_authentication_mode                 = "API"
bootstrap_cluster_creator_admin_permissions = false
cluster_upgrade_support_type                = "STANDARD"
cluster_create_timeout                      = "40m"
cluster_delete_timeout                      = "30m"
endpoint_private_access                     = true
endpoint_public_access                      = true
log_retention_days                          = 90
access_scope_namespace                      = "namespace"

allow_effect           = "Allow"
service_principal_type = "Service"
any_resource           = ["*"]

service_trust_principals = {
  cluster      = "eks.amazonaws.com"
  node         = "ec2.amazonaws.com"
  pod_identity = "pods.eks.amazonaws.com"
}
service_trust_actions = {
  cluster      = "sts:AssumeRole"
  node         = "sts:AssumeRole"
  pod_identity = ["sts:AssumeRole", "sts:TagSession"]
}

cluster_role_managed_policy = "AmazonEKSClusterPolicy"
ebs_csi_managed_policy      = "service-role/AmazonEBSCSIDriverPolicy"
node_managed_policies = [
  "AmazonEKSWorkerNodePolicy",
  "AmazonEC2ContainerRegistryReadOnly",
  "AmazonEKS_CNI_Policy",
  "AmazonSSMManagedInstanceCore",
]

karpenter_discovery_tag_key = "karpenter.sh/discovery"

system_node_group_name = "system"
system_ami_type        = "BOTTLEROCKET_ARM_64"
system_max_unavailable = 1
system_update_strategy = "MINIMAL"
system_taint = {
  key    = "CriticalAddonsOnly"
  value  = "true"
  effect = "NO_SCHEDULE"
}
system_labels = {
  role = "system"
}

addon_names = {
  coredns                = "coredns"
  kube_proxy             = "kube-proxy"
  vpc_cni                = "vpc-cni"
  eks_pod_identity_agent = "eks-pod-identity-agent"
  aws_ebs_csi_driver     = "aws-ebs-csi-driver"
}
addon_resolve_conflicts = "OVERWRITE"
ebs_csi_controller_toleration = {
  key      = "CriticalAddonsOnly"
  operator = "Exists"
}
ebs_csi_namespace       = "kube-system"
ebs_csi_service_account = "ebs-csi-controller-sa"

karpenter_node_access_entry_type  = "EC2_LINUX"
karpenter_queue_retention_seconds = 300
karpenter_queue_sse_enabled       = true
karpenter_queue_policy_sid        = "AllowEventBridge"
karpenter_queue_policy_actions    = ["sqs:SendMessage"]
karpenter_queue_policy_principals = ["events.amazonaws.com", "sqs.amazonaws.com"]
karpenter_events = {
  spot-interruption = {
    source      = "aws.ec2"
    detail_type = "EC2 Spot Instance Interruption Warning"
  }
  rebalance = {
    source      = "aws.ec2"
    detail_type = "EC2 Instance Rebalance Recommendation"
  }
  instance-state-change = {
    source      = "aws.ec2"
    detail_type = "EC2 Instance State-change Notification"
  }
  scheduled-change = {
    source      = "aws.health"
    detail_type = "AWS Health Event"
  }
}

karpenter_controller_policy_name = "karpenter-controller"
karpenter_namespace              = "kube-system"
karpenter_service_account        = "karpenter"

karpenter_compute_sid = "Compute"
karpenter_compute_actions = [
  "ec2:RunInstances",
  "ec2:CreateFleet",
  "ec2:CreateLaunchTemplate",
  "ec2:CreateTags",
  "ec2:TerminateInstances",
  "ec2:DeleteLaunchTemplate",
  "ec2:DescribeInstances",
  "ec2:DescribeInstanceTypes",
  "ec2:DescribeInstanceTypeOfferings",
  "ec2:DescribeLaunchTemplates",
  "ec2:DescribeImages",
  "ec2:DescribeSecurityGroups",
  "ec2:DescribeSubnets",
  "ec2:DescribeSpotPriceHistory",
  "ec2:DescribeAvailabilityZones",
]
karpenter_pricing_sid      = "Pricing"
karpenter_pricing_actions  = ["pricing:GetProducts"]
karpenter_interruption_sid = "Interruption"
karpenter_interruption_actions = [
  "sqs:DeleteMessage",
  "sqs:GetQueueUrl",
  "sqs:ReceiveMessage",
]
karpenter_pass_node_role_sid     = "PassNodeRole"
karpenter_pass_node_role_actions = ["iam:PassRole"]
karpenter_instance_profile_sid   = "InstanceProfile"
karpenter_instance_profile_actions = [
  "iam:CreateInstanceProfile",
  "iam:TagInstanceProfile",
  "iam:AddRoleToInstanceProfile",
  "iam:RemoveRoleFromInstanceProfile",
  "iam:DeleteInstanceProfile",
  "iam:GetInstanceProfile",
  "iam:ListInstanceProfiles",
]
karpenter_eks_sid     = "EKS"
karpenter_eks_actions = ["eks:DescribeCluster"]
karpenter_ssm_sid     = "SSM"
karpenter_ssm_actions = ["ssm:GetParameter"]

eks_ssm_namespace = "eks"
ssm_param_type    = "String"

dns_ssm_namespace = "dns"
dns_zone_id_key   = "zone-id"

alb_policy_name     = "alb-controller"
alb_policy_file     = "alb-iam-policy.json"
alb_namespace       = "kube-system"
alb_service_account = "aws-load-balancer-controller"

eso_policy_name     = "eso"
eso_namespace       = "external-secrets"
eso_service_account = "external-secrets"
eso_ssm_sid         = "SSMRead"
eso_ssm_actions = [
  "ssm:GetParameter",
  "ssm:GetParameters",
  "ssm:GetParametersByPath",
  "ssm:DescribeParameters",
]
eso_secrets_sid = "SecretsManagerRead"
eso_secrets_actions = [
  "secretsmanager:GetSecretValue",
  "secretsmanager:DescribeSecret",
  "secretsmanager:ListSecrets",
]

external_dns_policy_name     = "external-dns"
external_dns_namespace       = "external-dns"
external_dns_service_account = "external-dns"
external_dns_change_sid      = "ChangeRecords"
external_dns_change_actions  = ["route53:ChangeResourceRecordSets"]
external_dns_list_sid        = "ListZones"
external_dns_list_actions = [
  "route53:ListHostedZones",
  "route53:ListResourceRecordSets",
  "route53:ListTagsForResources",
]

keda_policy_name        = "keda-scalers"
keda_namespace          = "keda"
keda_service_account    = "keda-operator"
keda_cloudwatch_sid     = "CloudWatchMetrics"
keda_cloudwatch_actions = ["cloudwatch:GetMetricData"]
keda_sqs_sid            = "SqsQueueLength"
keda_sqs_actions        = ["sqs:GetQueueAttributes"]

thanos_policy_key               = "thanos-policy-arn"
thanos_count                    = 1
keda_count                      = 0
thanos_namespace                = "monitoring"
thanos_service_accounts         = ["thanos-compact", "thanos-receive-ingestor", "thanos-store-gateway"]
extra_pod_identity_associations = {}
