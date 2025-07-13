# 🚀 Terraform AWS ECS Deployment

This project uses Terraform to provision and manage two types of ECS architectures on AWS:

1. **Fargate-based ECS Cluster** with Application Load Balancer and Auto Scaling
2. **EC2-based ECS Cluster** with Auto Scaling Group and Application Load Balancer

---

## 📁 Project Structure

| File Name                            | Purpose                                                   |
|--------------------------------------|-----------------------------------------------------------|
| `main_simple_ecs.tf`                | Minimal ECS cluster setup (starting point)               |
| `main_ecs_alb_farget.tf`            | Fargate ECS cluster + ALB (no autoscaling)               |
| `main_ecs_alb_autoscaling_farget.tf`| Fargate ECS with ALB + target-tracking autoscaling       |
| `main_ecs_ec2_alb_autoscaling.tf`   | EC2-backed ECS cluster with ALB + Auto Scaling Group     |
| `output.tf`                          | Outputs such as ALB DNS name, ECS service info           |

---

## 🛠 Prerequisites

- Terraform >= 1.3
- AWS CLI configured (`aws configure`)
- AWS IAM user with permissions for ECS, EC2, IAM, Auto Scaling, ALB, VPC

---

## 🔧 How to Use

### 1. Initialize Terraform

```bash
terraform init
2. Plan the Deployment
Choose the ECS variant you want to deploy:

▶ Example: Fargate with ALB and Auto Scaling
bash
Copy
Edit
terraform plan -target=module.main_ecs_alb_autoscaling_farget
▶ Example: EC2-backed ECS with ALB
bash
Copy
Edit
terraform plan -target=module.main_ecs_ec2_alb_autoscaling
You can also comment/uncomment the appropriate .tf files depending on the variant you want.

3. Apply the Deployment
bash
Copy
Edit
terraform apply
🌐 Output
After deployment, Terraform will output:

ECS Cluster name

ALB DNS name (for accessing NGINX or app)

You can test the deployment by hitting the ALB DNS in your browser:

bash
Copy
Edit
curl http://<alb_dns_name>
⚙️ Destroy Resources
To tear down everything:

bash
Copy
Edit
terraform destroy
📌 Notes
ALB requires subnets in at least 2 Availability Zones

Make sure your VPC and subnets are created correctly with map_public_ip_on_launch = true for public ALB access

Use random_id resource for IAM role naming to avoid conflicts

If you encounter EntityAlreadyExists or Security Group not in VPC errors, refer to TROUBLESHOOTING.md (add your guide here)
