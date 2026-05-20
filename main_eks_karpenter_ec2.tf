provider "aws" {
  region = "us-east-2"
}

# VPC
resource "aws_vpc" "eks_karpenter_vpc" {
  cidr_block           = "10.2.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "eks-karpenter-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "eks_karpenter_igw" {
  vpc_id = aws_vpc.eks_karpenter_vpc.id

  tags = {
    Name = "eks-karpenter-igw"
  }
}

# Public Subnets
resource "aws_subnet" "eks_karpenter_subnet1" {
  vpc_id                  = aws_vpc.eks_karpenter_vpc.id
  cidr_block              = "10.2.1.0/24"
  availability_zone       = "us-east-2a"
  map_public_ip_on_launch = true

  tags = {
    Name = "eks-karpenter-subnet-1"
    "karpenter.sh/discovery" = "eks-karpenter-cluster"
  }
}

resource "aws_subnet" "eks_karpenter_subnet2" {
  vpc_id                  = aws_vpc.eks_karpenter_vpc.id
  cidr_block              = "10.2.2.0/24"
  availability_zone       = "us-east-2b"
  map_public_ip_on_launch = true

  tags = {
    Name = "eks-karpenter-subnet-2"
    "karpenter.sh/discovery" = "eks-karpenter-cluster"
  }
}

# Route Table
resource "aws_route_table" "eks_karpenter_rt" {
  vpc_id = aws_vpc.eks_karpenter_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks_karpenter_igw.id
  }

  tags = {
    Name = "eks-karpenter-rt"
  }
}

# Route Table Associations
resource "aws_route_table_association" "eks_karpenter_rta1" {
  subnet_id      = aws_subnet.eks_karpenter_subnet1.id
  route_table_id = aws_route_table.eks_karpenter_rt.id
}

resource "aws_route_table_association" "eks_karpenter_rta2" {
  subnet_id      = aws_subnet.eks_karpenter_subnet2.id
  route_table_id = aws_route_table.eks_karpenter_rt.id
}

# Security Groups
resource "aws_security_group" "eks_karpenter_cluster_sg" {
  name   = "eks-karpenter-cluster-sg"
  vpc_id = aws_vpc.eks_karpenter_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eks-karpenter-cluster-sg"
  }
}

resource "aws_security_group" "eks_karpenter_node_sg" {
  name   = "eks-karpenter-node-sg"
  vpc_id = aws_vpc.eks_karpenter_vpc.id

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.2.0.0/16"]
  }

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "udp"
    cidr_blocks = ["10.2.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eks-karpenter-node-sg"
    "karpenter.sh/discovery" = "eks-karpenter-cluster"
  }
}

# IAM Role for EKS Cluster
resource "aws_iam_role" "eks_karpenter_cluster_role" {
  name = "eks-karpenter-cluster-role"

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
    Name = "eks-karpenter-cluster-role"
  }
}

resource "aws_iam_role_policy_attachment" "eks_karpenter_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_karpenter_cluster_role.name
}

# EKS Cluster
resource "aws_eks_cluster" "eks_karpenter" {
  name            = "eks-karpenter-cluster"
  role_arn        = aws_iam_role.eks_karpenter_cluster_role.arn
  version         = "1.28"

  vpc_config {
    subnet_ids              = [aws_subnet.eks_karpenter_subnet1.id, aws_subnet.eks_karpenter_subnet2.id]
    security_group_ids      = [aws_security_group.eks_karpenter_cluster_sg.id]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  depends_on = [aws_iam_role_policy_attachment.eks_karpenter_cluster_policy]

  tags = {
    Name = "eks-karpenter-cluster"
  }
}

# IAM Role for EKS Node Group
resource "aws_iam_role" "eks_karpenter_node_role" {
  name = "eks-karpenter-node-role"

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
    Name = "eks-karpenter-node-role"
  }
}

resource "aws_iam_role_policy_attachment" "eks_karpenter_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_karpenter_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_karpenter_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_karpenter_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_karpenter_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_karpenter_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_karpenter_ssm_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.eks_karpenter_node_role.name
}

# Initial Node Group (required for Karpenter provisioning)
resource "aws_eks_node_group" "karpenter_initial" {
  cluster_name    = aws_eks_cluster.eks_karpenter.name
  node_group_name = "karpenter-initial-nodes"
  node_role_arn   = aws_iam_role.eks_karpenter_node_role.arn
  subnet_ids      = [aws_subnet.eks_karpenter_subnet1.id, aws_subnet.eks_karpenter_subnet2.id]
  version         = "1.28"

  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 2
  }

  instance_types = ["t3.medium"]

  tags = {
    Name = "karpenter-initial-nodes"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_karpenter_node_policy,
    aws_iam_role_policy_attachment.eks_karpenter_cni_policy,
    aws_iam_role_policy_attachment.eks_karpenter_registry_policy,
  ]
}

# IAM Role for Karpenter Controller
resource "aws_iam_role" "karpenter_controller_role" {
  name = "karpenter-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(aws_eks_cluster.eks_karpenter.identity[0].oidc[0].issuer, "https://", "")}"
      }
      Condition = {
        StringEquals = {
          "${replace(aws_eks_cluster.eks_karpenter.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:karpenter:karpenter"
        }
      }
    }]
  })

  tags = {
    Name = "karpenter-controller-role"
  }
}

# Karpenter Controller Policy
resource "aws_iam_role_policy" "karpenter_controller_policy" {
  name   = "karpenter-controller-policy"
  role   = aws_iam_role.karpenter_controller_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateFleet",
          "ec2:CreateLaunchTemplate",
          "ec2:CreateInstances",
          "ec2:CreateTags",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeTags",
          "ec2:DescribeVpcs",
          "ec2:GetInstanceTypesFromInstanceRequirements",
          "pricing:GetProducts"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:TerminateInstances",
          "ec2:DeleteLaunchTemplate"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/karpenter.sh/provisioner" = "*"
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = "arn:aws:ssm:*:*:parameter/aws/service/eks/optimized-ami/*"
      }
    ]
  })
}

# Data source for AWS Account ID
data "aws_caller_identity" "current" {}
