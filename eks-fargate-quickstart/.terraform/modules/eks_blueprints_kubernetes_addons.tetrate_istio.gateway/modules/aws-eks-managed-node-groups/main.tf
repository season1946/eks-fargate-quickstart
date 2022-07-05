resource "aws_eks_node_group" "managed_ng" {
  cluster_name           = var.context.eks_cluster_id
  node_group_name_prefix = local.managed_node_group["node_group_name"]
  node_role_arn          = aws_iam_role.managed_ng.arn
  subnet_ids             = length(local.managed_node_group["subnet_ids"]) == 0 ? (local.managed_node_group["subnet_type"] == "public" ? var.context.public_subnet_ids : var.context.private_subnet_ids) : local.managed_node_group["subnet_ids"]
  release_version        = try(local.managed_node_group["release_version"], "") == "" ? null : local.managed_node_group["release_version"]

  ami_type       = local.managed_node_group["ami_type"] != "" ? local.managed_node_group["ami_type"] : null
  capacity_type  = local.managed_node_group["capacity_type"]
  disk_size      = local.managed_node_group["create_launch_template"] == true ? null : local.managed_node_group["disk_size"]
  instance_types = local.managed_node_group["instance_types"]

  scaling_config {
    desired_size = local.managed_node_group["desired_size"]
    max_size     = local.managed_node_group["max_size"]
    min_size     = local.managed_node_group["min_size"]
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [scaling_config[0].desired_size]
  }

  dynamic "launch_template" {
    for_each = local.managed_node_group["create_launch_template"] == true ? [{
      id      = aws_launch_template.managed_node_groups.id
      version = aws_launch_template.managed_node_groups.default_version
    }] : []
    content {
      id      = launch_template.value["id"]
      version = launch_template.value["version"]
    }
  }

  dynamic "remote_access" {
    for_each = local.managed_node_group["remote_access"] == true ? [1] : []
    content {
      ec2_ssh_key               = local.managed_node_group["ec2_ssh_key"]
      source_security_group_ids = local.managed_node_group["ssh_security_group_id"]
    }
  }

  dynamic "taint" {
    for_each = local.managed_node_group["k8s_taints"]
    content {
      key    = taint.value["key"]
      value  = taint.value["value"]
      effect = taint.value["effect"]
    }
  }

  labels = local.managed_node_group["k8s_labels"]

  tags = local.common_tags

  timeouts {
    create = "2h"
    update = "2h"
    delete = "2h"
  }

  depends_on = [
    aws_iam_role.managed_ng,
    aws_iam_instance_profile.managed_ng,
    aws_iam_role_policy_attachment.managed_ng
  ]

}
