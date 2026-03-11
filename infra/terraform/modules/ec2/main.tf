variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "name_suffix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "user_data_template" {
  type = string
}

variable "user_data_vars" {
  type = map(string)
}

variable "ingress_rules" {
  type = list(object({
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
    description = string
  }))
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_security_group" "main" {
  name        = "${var.project_name}-${var.environment}-${var.name_suffix}-sg"
  description = "Security group for ${var.name_suffix}"
  vpc_id      = var.vpc_id
  
  dynamic "ingress" {
    for_each = var.ingress_rules
    content {
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
      description = ingress.value.description
    }
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  
  tags = {
    Name = "${var.project_name}-${var.environment}-${var.name_suffix}-sg"
  }
}

resource "aws_iam_role" "main" {
  name = "${var.project_name}-${var.environment}-${var.name_suffix}-role"
  
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
}

resource "aws_iam_role_policy_attachment" "ssm_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.main.name
}

resource "aws_iam_instance_profile" "main" {
  name = "${var.project_name}-${var.environment}-${var.name_suffix}-profile"
  role = aws_iam_role.main.name
}

resource "aws_instance" "main" {
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = var.instance_type
  subnet_id     = var.subnet_id
  
  vpc_security_group_ids = [aws_security_group.main.id]
  iam_instance_profile   = aws_iam_instance_profile.main.name
  
  user_data = templatefile(var.user_data_template, var.user_data_vars)
  
  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }
  
  tags = {
    Name = "${var.project_name}-${var.environment}-${var.name_suffix}"
  }
}

output "instance_id" {
  value = aws_instance.main.id
}

output "public_ip" {
  value = aws_instance.main.public_ip
}

output "private_ip" {
  value = aws_instance.main.private_ip
}

output "security_group_id" {
  value = aws_security_group.main.id
}
