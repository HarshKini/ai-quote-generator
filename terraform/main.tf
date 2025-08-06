terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"  # Cheapest region with full free tier
}

# Variables (optimized for minimal cost)
variable "aws_region" {
  description = "AWS region optimized for cost"
  default     = "us-east-1"  # Lowest pricing + largest free tier
}

variable "instance_type" {
  description = "EC2 instance type - t2.micro is free tier eligible"
  default     = "t2.micro"
}

variable "project_name" {
  default = "ai-quote-generator"
}

# Add the missing OpenAI API key variable
variable "openai_api_key" {
  description = "OpenAI API key for the application"
  type        = string
  sensitive   = true
}

# S3 Bucket for static files (us-east-1 = cheapest)
resource "aws_s3_bucket" "app_bucket" {
  bucket = "${var.project_name}-bucket-${random_string.suffix.result}"
}

resource "aws_s3_bucket_public_access_block" "app_bucket_pab" {
  bucket = aws_s3_bucket.app_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Cost optimization: Standard storage class (cheapest for small files)
resource "aws_s3_bucket_lifecycle_configuration" "app_bucket_lifecycle" {
  bucket = aws_s3_bucket.app_bucket.id

  rule {
    id     = "cost_optimization"
    status = "Enabled"
    
    # Add filter to fix the warning
    filter {}

    transition {
      days          = 30
      storage_class = "STANDARD_IA"  # Cheaper after 30 days
    }
  }
}

resource "random_string" "suffix" {
  length  = 6  # Shorter suffix to save on naming costs
  special = false
  upper   = false
}

# EC2 Instance (US East 1 optimized)
resource "aws_instance" "app_server" {
  ami           = "ami-0866a3c8686eaeeba" # Latest Ubuntu 22.04 LTS in us-east-1 (Nov 2024)
  instance_type = var.instance_type        # t2.micro - Free tier eligible

  key_name = aws_key_pair.deployer.key_name

  vpc_security_group_ids = [aws_security_group.web_sg.id]

  # Optimized user data for minimal resource usage
  user_data = base64encode(<<-EOF
    #!/bin/bash
    apt update && apt install -y python3-pip nginx git
    pip3 install flask flask-cors openai

    # Clone and setup app (replace with your repo)
    cd /home/ubuntu
    git clone https://github.com/YOUR_USERNAME/ai-quote-generator.git
    cd ai-quote-generator

    # Set OpenAI API key as environment variable
    echo "export OPENAI_API_KEY='${var.openai_api_key}'" >> /etc/environment

    # Setup nginx reverse proxy
    cat > /etc/nginx/sites-available/default << 'EOL'
server {
    listen 80;
    server_name _;

    location / {
        root /home/ubuntu/ai-quote-generator/frontend;
        try_files $uri $uri/ /index.html;
    }

    location /generate-quote {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /health {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOL

    # Start services
    systemctl restart nginx
    cd /home/ubuntu/ai-quote-generator/backend
    nohup python3 app.py > /var/log/app.log 2>&1 &
  EOF
  )

  tags = {
    Name        = "${var.project_name}-server"
    Environment = "learning"
    CostCenter  = "free-tier"
  }
}

# Security Group
resource "aws_security_group" "web_sg" {
  name_prefix = "${var.project_name}-sg"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
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

# Key Pair for SSH
resource "aws_key_pair" "deployer" {
  key_name   = "${var.project_name}-key"
  public_key = file("~/.ssh/id_rsa.pub")
}

# Output the public IP
output "public_ip" {
  value = aws_instance.app_server.public_ip
}
