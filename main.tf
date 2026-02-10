provider "aws" {
  region = "us-east-1"
}

################################
# VPC
################################
resource "aws_vpc" "ketan_devops_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "ketan-devops-vpc" }
}

resource "aws_subnet" "ketan_devops_subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.ketan_devops_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.ketan_devops_vpc.cidr_block, 8, count.index)
  availability_zone       = element(["us-east-1a", "us-east-1b"], count.index)
  map_public_ip_on_launch = true
  tags = { Name = "ketan-devops-subnet-${count.index}" }
}

resource "aws_internet_gateway" "ketan_devops_igw" {
  vpc_id = aws_vpc.ketan_devops_vpc.id
  tags = { Name = "ketan-devops-igw" }
}

resource "aws_route_table" "ketan_devops_route_table" {
  vpc_id = aws_vpc.ketan_devops_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ketan_devops_igw.id
  }
  tags = { Name = "ketan-devops-route-table" }
}

resource "aws_route_table_association" "ketan_devops_association" {
  count          = 2
  subnet_id      = aws_subnet.ketan_devops_subnet[count.index].id
  route_table_id = aws_route_table.ketan_devops_route_table.id
}

################################
# Security Groups
################################
resource "aws_security_group" "ketan_devops_cluster_sg" {
  vpc_id = aws_vpc.ketan_devops_vpc.id
  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "ketan-devops-cluster-sg" }
}

resource "aws_security_group" "ketan_devops_node_sg" {
  vpc_id = aws_vpc.ketan_devops_vpc.id
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "ketan-devops-node-sg" }
}

################################
# IAM ROLES
################################
resource "aws_iam_role" "ketan_devops_cluster_role" {
  name = "ketan-devops-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.ketan_devops_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "ketan_devops_node_group_role" {
  name = "ketan-devops-node-group-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.ketan_devops_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.ketan_devops_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.ketan_devops_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

################################
# EKS CLUSTER
################################
resource "aws_eks_cluster" "ketan_devops" {
  name     = "ketan-devops-cluster"
  role_arn = aws_iam_role.ketan_devops_cluster_role.arn

  vpc_config {
    subnet_ids         = aws_subnet.ketan_devops_subnet[*].id
    security_group_ids = [aws_security_group.ketan_devops_cluster_sg.id]
  }
}

################################
# NODE GROUP
################################
resource "aws_eks_node_group" "ketan_devops" {
  cluster_name    = aws_eks_cluster.ketan_devops.name
  node_group_name = "ketan-devops-node-group"
  node_role_arn   = aws_iam_role.ketan_devops_node_group_role.arn
  subnet_ids      = aws_subnet.ketan_devops_subnet[*].id

  instance_types = ["t2.medium"]

  scaling_config {
    desired_size = 3
    min_size     = 3
    max_size     = 3
  }
}

################################
# IRSA + EBS CSI DRIVER
################################
data "aws_eks_cluster" "eks" {
  name = aws_eks_cluster.ketan_devops.name
}

locals {
  oidc_issuer = replace(data.aws_eks_cluster.eks.identity[0].oidc[0].issuer, "https://", "")
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = data.aws_eks_cluster.eks.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["9e99a48a9960b14926bb7f3b02e22da0afd30df7"]
}

resource "aws_iam_role" "ebs_csi_irsa_role" {
  name = "AmazonEKS_EBS_CSI_DriverRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi_policy" {
  role       = aws_iam_role.ebs_csi_irsa_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name = aws_eks_cluster.ketan_devops.name
  addon_name   = "aws-ebs-csi-driver"

  service_account_role_arn = aws_iam_role.ebs_csi_irsa_role.arn

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_node_group.ketan_devops,
    aws_iam_role_policy_attachment.ebs_csi_policy
  ]
}
