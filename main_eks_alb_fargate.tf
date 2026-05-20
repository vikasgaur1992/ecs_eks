provider "aws" {
  region = "us-east-2"
}

# VPC
resource "aws_vpc" "eks_alb_vpc" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "eks-alb-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "eks_alb_igw" {
  vpc_id = aws_vpc.eks_alb_vpc.id

  tags = {
    Name = "eks-alb-igw"
  }
}

# Public Subnets
resource "aws_subnet" "eks_alb_subnet1" {
  vpc_id                  = aws_vpc.eks_alb_vpc.id
  cidr_block              = "10.1.1.0/24"
  availability_zone       = "us-east-2a"
  map_public_ip_on_launch = true

  tags = {
    Name                                    = "eks-alb-subnet-1"
    "kubernetes.io/role/elb"                = "1"
  }
}

resource "aws_subnet" "eks_alb_subnet2" {
  vpc_id                  = aws_vpc.eks_alb_vpc.id
  cidr_block              = "10.1.2.0/24"
  availability_zone       = "us-east-2b"
  map_public_ip_on_launch = true

  tags = {
    Name                                    = "eks-alb-subnet-2"
    "kubernetes.io/role/elb"                = "1"
  }
}

# Private Subnets for Fargate
resource "aws_subnet" "eks_alb_private_subnet1" {
  vpc_id            = aws_vpc.eks_alb_vpc.id
  cidr_block        = "10.1.11.0/24"
  availability_zone = "us-east-2a"

  tags = {
    Name                              = "eks-alb-private-subnet-1"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_subnet" "eks_alb_private_subnet2" {
  vpc_id            = aws_vpc.eks_alb_vpc.id
  cidr_block        = "10.1.12.0/24"
  availability_zone = "us-east-2b"

  tags = {
    Name                              = "eks-alb-private-subnet-2"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = {
    Name = "eks-alb-nat-eip"
  }

  depends_on = [aws_internet_gateway.eks_alb_igw]
}

# NAT Gateway
resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.eks_alb_subnet1.id

  tags = {
    Name = "eks-alb-nat-gw"
  }

  depends_on = [aws_internet_gateway.eks_alb_igw]
}

# Public Route Table
resource "aws_route_table" "eks_alb_public_rt" {
  vpc_id = aws_vpc.eks_alb_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks_alb_igw.id
  }

  tags = {
    Name = "eks-alb-public-rt"
  }
}

# Private Route Table
resource "aws_route_table" "eks_alb_private_rt" {
  vpc_id = aws_vpc.eks_alb_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }

  tags = {
    Name = "eks-alb-private-rt"
  }
}

# Route Table Associations
resource "aws_route_table_association" "eks_alb_public_rta1" {
  subnet_id      = aws_subnet.eks_alb_subnet1.id
  route_table_id = aws_route_table.eks_alb_public_rt.id
}

resource "aws_route_table_association" "eks_alb_public_rta2" {
  subnet_id      = aws_subnet.eks_alb_subnet2.id
  route_table_id = aws_route_table.eks_alb_public_rt.id
}

resource "aws_route_table_association" "eks_alb_private_rta1" {
  subnet_id      = aws_subnet.eks_alb_private_subnet1.id
  route_table_id = aws_route_table.eks_alb_private_rt.id
}

resource "aws_route_table_association" "eks_alb_private_rta2" {
  subnet_id      = aws_subnet.eks_alb_private_subnet2.id
  route_table_id = aws_route_table.eks_alb_private_rt.id
}

# Security Groups
resource "aws_security_group" "eks_alb_cluster_sg" {
  name   = "eks-alb-cluster-sg"
  vpc_id = aws_vpc.eks_alb_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eks-alb-cluster-sg"
  }
}

resource "aws_security_group" "eks_alb_fargate_sg" {
  name   = "eks-alb-fargate-sg"
  vpc_id = aws_vpc.eks_alb_vpc.id

  ingress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_alb_alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eks-alb-fargate-sg"
  }
}

resource "aws_security_group" "eks_alb_alb_sg" {
  name   = "eks-alb-alb-sg"
  vpc_id = aws_vpc.eks_alb_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eks-alb-alb-sg"
  }
}

# IAM Role for EKS Cluster
resource "aws_iam_role" "eks_alb_cluster_role" {
  name = "eks-alb-cluster-role"

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
    Name = "eks-alb-cluster-role"
  }
}

resource "aws_iam_role_policy_attachment" "eks_alb_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_alb_cluster_role.name
}

# EKS Cluster
resource "aws_eks_cluster" "eks_alb" {
  name            = "eks-alb-fargate-cluster"
  role_arn        = aws_iam_role.eks_alb_cluster_role.arn
  version         = "1.28"

  vpc_config {
    subnet_ids              = concat([aws_subnet.eks_alb_subnet1.id, aws_subnet.eks_alb_subnet2.id], [aws_subnet.eks_alb_private_subnet1.id, aws_subnet.eks_alb_private_subnet2.id])
    security_group_ids      = [aws_security_group.eks_alb_cluster_sg.id]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  depends_on = [aws_iam_role_policy_attachment.eks_alb_cluster_policy]

  tags = {
    Name = "eks-alb-fargate-cluster"
  }
}

# IAM Role for Fargate Pod Execution
resource "aws_iam_role" "eks_alb_fargate_pod_role" {
  name = "eks-alb-fargate-pod-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks-fargate-pods.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "eks-alb-fargate-pod-execution-role"
  }
}

resource "aws_iam_role_policy_attachment" "eks_alb_fargate_pod_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
  role       = aws_iam_role.eks_alb_fargate_pod_role.name
}

# Fargate Profile
resource "aws_eks_fargate_profile" "main" {
  cluster_name           = aws_eks_cluster.eks_alb.name
  fargate_profile_name   = "alb-fargate-profile"
  pod_execution_role_arn = aws_iam_role.eks_alb_fargate_pod_role.arn
  subnet_ids             = [aws_subnet.eks_alb_private_subnet1.id, aws_subnet.eks_alb_private_subnet2.id]

  selector {
    namespace = "default"
  }

  selector {
    namespace = "kube-system"
  }

  tags = {
    Name = "alb-fargate-profile"
  }

  depends_on = [aws_iam_role_policy_attachment.eks_alb_fargate_pod_policy]
}

# Application Load Balancer
resource "aws_lb" "eks_alb" {
  name               = "eks-alb-fargate-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.eks_alb_alb_sg.id]
  subnets            = [aws_subnet.eks_alb_subnet1.id, aws_subnet.eks_alb_subnet2.id]

  tags = {
    Name = "eks-alb-fargate-alb"
  }
}

# Target Group
resource "aws_lb_target_group" "eks_alb_tg" {
  name        = "eks-alb-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.eks_alb_vpc.id
  target_type = "ip"

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200-399"
  }

  tags = {
    Name = "eks-alb-tg"
  }
}

# Listener
resource "aws_lb_listener" "eks_alb_listener" {
  load_balancer_arn = aws_lb.eks_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.eks_alb_tg.arn
  }

  tags = {
    Name = "eks-alb-listener"
  }
}
