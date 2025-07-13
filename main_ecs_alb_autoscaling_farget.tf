provider "aws" {
  region = "us-east-2"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "rta" {
  subnet_id      = aws_subnet.subnet.id
  route_table_id = aws_route_table.rt.id
}

resource "aws_subnet" "subnet" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  availability_zone       = "us-east-2a" # Different AZ than subnet
  map_public_ip_on_launch = true # Enable public IP assignment
}

# Add a second public subnet in a different AZ
resource "aws_subnet" "subnet2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-2b" # Different AZ than subnet1
  map_public_ip_on_launch = true
}

# Associate the second subnet to the route table
resource "aws_route_table_association" "rta2" {
  subnet_id      = aws_subnet.subnet2.id
  route_table_id = aws_route_table.rt.id
}


# ECS Cluster
resource "aws_ecs_cluster" "demo" {
  name = "demo-cluster"
}

# IAM Role for task execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole_demo"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task Definition
resource "aws_ecs_task_definition" "demo_task" {
  family                   = "demo-task"
  requires_compatibilities = ["FARGATE"]
  network_mode            = "awsvpc"
  cpu                     = "256"
  memory                  = "512"
  execution_role_arn      = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([{
    name      = "demo"
    image     = "nginx"
    essential = true
    portMappings = [{
      containerPort = 80
      hostPort      = 80
    }]
  }])
}

# Security Group
resource "aws_security_group" "ecs_sg" {
  name   = "ecs-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ECS Service
resource "aws_ecs_service" "demo_service" {
  name            = "demo-service"
  cluster         = aws_ecs_cluster.demo.id
  task_definition = aws_ecs_task_definition.demo_task.arn
  launch_type     = "FARGATE"
   desired_count  = 1

  network_configuration {
    subnets         = [aws_subnet.subnet.id]
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

    load_balancer {
    target_group_arn = aws_lb_target_group.tg.arn
    container_name   = "demo"
    container_port   = 80
  }

  depends_on = [aws_lb_listener.listener]
}

# ECS Auto Scaling Target
resource "aws_appautoscaling_target" "ecs_scaling_target" {
  max_capacity       = 4
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.demo.name}/${aws_ecs_service.demo_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# ECS Auto Scaling Policy
resource "aws_appautoscaling_policy" "ecs_scaling_policy" {
  name               = "cpu-scaling-policy"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_scaling_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_scaling_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_scaling_target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = 50.0
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    scale_in_cooldown  = 60
    scale_out_cooldown = 60
  }
}


# ALB Security Group
resource "aws_security_group" "alb_sg" {
  name   = "alb-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Application Load Balancer
resource "aws_lb" "alb" {
  name               = "demo-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
    subnets = [
    aws_subnet.subnet.id,
    aws_subnet.subnet2.id
  ]
}

# Target Group
resource "aws_lb_target_group" "tg" {
  name     = "demo-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
}

# Listener for ALB
resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}
