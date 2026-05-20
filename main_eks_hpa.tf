provider "aws" {
  region = "us-east-2"
}

# VPC
resource "aws_vpc" "eks_hpa_vpc" {
  cidr_block           = "10.3.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "eks-hpa-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "eks_hpa_igw" {
  vpc_id = aws_vpc.eks_hpa_vpc.id

  tags = {
    Name = "eks-hpa-igw"
  }
}

# Public Subnets
resource "aws_subnet" "eks_hpa_subnet1" {
  vpc_id                  = aws_vpc.eks_hpa_vpc.id
  cidr_block              = "10.3.1.0/24"
  availability_zone       = "us-east-2a"
  map_public_ip_on_launch = true

  tags = {
    Name = "eks-hpa-subnet-1"
  }
}

resource "aws_subnet" "eks_hpa_subnet2" {
  vpc_id                  = aws_vpc.eks_hpa_vpc.id
  cidr_block              = "10.3.2.0/24"
  availability_zone       = "us-east-2b"
  map_public_ip_on_launch = true

  tags = {
    Name = "eks-hpa-subnet-2"
  }
}

# Route Table
resource "aws_route_table" "eks_hpa_rt" {
  vpc_id = aws_vpc.eks_hpa_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks_hpa_igw.id
  }

  tags = {
    Name = "eks-hpa-rt"
  }
}

# Route Table Associations
resource "aws_route_table_association" "eks_hpa_rta1" {
  subnet_id      = aws_subnet.eks_hpa_subnet1.id
  route_table_id = aws_route_table.eks_hpa_rt.id
}

resource "aws_route_table_association" "eks_hpa_rta2" {
  subnet_id      = aws_subnet.eks_hpa_subnet2.id
  route_table_id = aws_route_table.eks_hpa_rt.id
}

# Security Groups
resource "aws_security_group" "eks_hpa_cluster_sg" {
  name   = "eks-hpa-cluster-sg"
  vpc_id = aws_vpc.eks_hpa_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eks-hpa-cluster-sg"
  }
}

resource "aws_security_group" "eks_hpa_node_sg" {
  name   = "eks-hpa-node-sg"
  vpc_id = aws_vpc.eks_hpa_vpc.id

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.3.0.0/16"]
  }

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "udp"
    cidr_blocks = ["10.3.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eks-hpa-node-sg"
  }
}

# IAM Role for EKS Cluster
resource "aws_iam_role" "eks_hpa_cluster_role" {
  name = "eks-hpa-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "eks-hpa-cluster-role"
  }
}

resource "aws_iam_role_policy_attachment" "eks_hpa_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_hpa_cluster_role.name
}

# EKS Cluster
resource "aws_eks_cluster" "eks_hpa" {
  name            = "eks-hpa-cluster"
  role_arn        = aws_iam_role.eks_hpa_cluster_role.arn
  version         = "1.28"

  vpc_config {
    subnet_ids              = [aws_subnet.eks_hpa_subnet1.id, aws_subnet.eks_hpa_subnet2.id]
    security_group_ids      = [aws_security_group.eks_hpa_cluster_sg.id]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  depends_on = [aws_iam_role_policy_attachment.eks_hpa_cluster_policy]

  tags = {
    Name = "eks-hpa-cluster"
  }
}

# IAM Role for EKS Node Group
resource "aws_iam_role" "eks_hpa_node_role" {
  name = "eks-hpa-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "eks-hpa-node-role"
  }
}

resource "aws_iam_role_policy_attachment" "eks_hpa_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_hpa_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_hpa_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_hpa_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_hpa_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_hpa_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_hpa_cloudwatch_policy" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.eks_hpa_node_role.name
}

# EKS Node Group with Monitoring Enabled
resource "aws_eks_node_group" "hpa_nodes" {
  cluster_name    = aws_eks_cluster.eks_hpa.name
  node_group_name = "hpa-node-group"
  node_role_arn   = aws_iam_role.eks_hpa_node_role.arn
  subnet_ids      = [aws_subnet.eks_hpa_subnet1.id, aws_subnet.eks_hpa_subnet2.id]
  version         = "1.28"

  scaling_config {
    desired_size = 3
    max_size     = 10
    min_size     = 2
  }

  instance_types = ["t3.small"]

  # Enable detailed monitoring
  tags = {
    Name = "hpa-node-group"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_hpa_node_policy,
    aws_iam_role_policy_attachment.eks_hpa_cni_policy,
    aws_iam_role_policy_attachment.eks_hpa_registry_policy,
  ]
}

# IAM Role for Metrics Server
resource "aws_iam_role" "metrics_server_role" {
  name = "eks-hpa-metrics-server-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${data.aws_caller_identity.hpa.account_id}:oidc-provider/${replace(aws_eks_cluster.eks_hpa.identity[0].oidc[0].issuer, "https://", "")}"
      }
      Condition = {
        StringEquals = {
          "${replace(aws_eks_cluster.eks_hpa.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:kube-system:metrics-server"
        }
      }
    }]
  })

  tags = {
    Name = "eks-hpa-metrics-server-role"
  }
}

# Policy for Metrics Server (minimal permissions)
resource "aws_iam_role_policy" "metrics_server_policy" {
  name   = "eks-hpa-metrics-server-policy"
  role   = aws_iam_role.metrics_server_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM Role for HPA Controller
resource "aws_iam_role" "hpa_controller_role" {
  name = "eks-hpa-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${data.aws_caller_identity.hpa.account_id}:oidc-provider/${replace(aws_eks_cluster.eks_hpa.identity[0].oidc[0].issuer, "https://", "")}"
      }
      Condition = {
        StringEquals = {
          "${replace(aws_eks_cluster.eks_hpa.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:kube-system:horizontal-pod-autoscaler"
        }
      }
    }]
  })

  tags = {
    Name = "eks-hpa-controller-role"
  }
}

# Policy for HPA Controller
resource "aws_iam_role_policy" "hpa_controller_policy" {
  name   = "eks-hpa-controller-policy"
  role   = aws_iam_role.hpa_controller_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
      }
    ]
  })
}

# CloudWatch Log Group for EKS Cluster Logs
resource "aws_cloudwatch_log_group" "eks_hpa_cluster_logs" {
  name              = "/aws/eks/eks-hpa-cluster/cluster"
  retention_in_days = 7

  tags = {
    Name = "eks-hpa-cluster-logs"
  }
}

# Data source for AWS Account ID
data "aws_caller_identity" "hpa" {}

# Outputs for HPA Configuration
output "eks_hpa_cluster_name" {
  value       = aws_eks_cluster.eks_hpa.name
  description = "EKS Cluster name for HPA"
}

output "eks_hpa_cluster_endpoint" {
  value       = aws_eks_cluster.eks_hpa.endpoint
  description = "EKS Cluster endpoint for HPA"
}

output "eks_hpa_cluster_version" {
  value       = aws_eks_cluster.eks_hpa.version
  description = "EKS Cluster version"
}

output "metrics_server_role_arn" {
  value       = aws_iam_role.metrics_server_role.arn
  description = "ARN of IAM role for Metrics Server"
}

output "hpa_controller_role_arn" {
  value       = aws_iam_role.hpa_controller_role.arn
  description = "ARN of IAM role for HPA Controller"
}
