output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.ketan_devops_vpc.id
}

output "subnet_ids" {
  description = "Subnet IDs"
  value       = aws_subnet.ketan_devops_subnet[*].id
}

output "eks_cluster_name" {
  description = "EKS Cluster Name"
  value       = aws_eks_cluster.ketan_devops.name
}

output "eks_cluster_endpoint" {
  description = "EKS Cluster API Server Endpoint"
  value       = aws_eks_cluster.ketan_devops.endpoint
}

output "eks_cluster_arn" {
  description = "EKS Cluster ARN"
  value       = aws_eks_cluster.ketan_devops.arn
}

output "node_group_name" {
  description = "EKS Node Group Name"
  value       = aws_eks_node_group.ketan_devops.node_group_name
}

output "cluster_security_group_id" {
  description = "Cluster security group ID"
  value       = aws_security_group.ketan_devops_cluster_sg.id
}

output "node_security_group_id" {
  description = "Node security group ID"
  value       = aws_security_group.ketan_devops_node_sg.id
}
