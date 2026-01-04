#################################
# Variables
#################################
variable "cidr" {
  type    = string
  default = "10.0.0.0/16"
}

#################################
# VPC
#################################
resource "aws_vpc" "my_vpc" {
  cidr_block           = var.cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "my_vpc"
  }
}

#################################
# Subnet
#################################
resource "aws_subnet" "my_vpc_subnet" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "my_vpc_subnet"
  }
}

#################################
# Internet Gateway
#################################
resource "aws_internet_gateway" "my_vpc_igw" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "my_vpc_igw"
  }
}

#################################
# Route Table
#################################
resource "aws_route_table" "my_vpc_rt" {
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_vpc_igw.id
  }

  tags = {
    Name = "my_vpc_rt"
  }
}

resource "aws_route_table_association" "my_vpc_rta" {
  subnet_id      = aws_subnet.my_vpc_subnet.id
  route_table_id = aws_route_table.my_vpc_rt.id
}

#################################
# Security Group
#################################
resource "aws_security_group" "my_vpc_sg" {
  name        = "my_vpc_sg"
  description = "Allow SSH and Flask traffic"
  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    description = "Flask App"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH Access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["167.103.21.18/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "my_vpc_sg"
  }
}

#################################
# Key Pair
#################################
resource "aws_key_pair" "my_ec2" {
  key_name   = "my_ec2"
  public_key = file("~/.ssh/id_rsa.pub") # use absolute path
}

#################################
# EC2 Instance
#################################
resource "aws_instance" "my_ec2_instance" {
  ami                         = "ami-02b8269d5e85954ef"
  instance_type               = "t2.micro"
  key_name                    = aws_key_pair.my_ec2.key_name
  subnet_id                   = aws_subnet.my_vpc_subnet.id
  vpc_security_group_ids      = [aws_security_group.my_vpc_sg.id]
  associate_public_ip_address = true

  tags = {
    Name = "my_ec2_instance"
  }

  #################################
  # SSH Connection
  #################################
  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("~/.ssh/id_rsa")
    host        = self.public_ip
  }

  #################################
  # File Provisioner
  #################################
  provisioner "file" {
    source      = "app.py"
    destination = "/home/ubuntu/app.py"
  }

  #################################
  # Remote Exec Provisioner
  #################################
  provisioner "remote-exec" {
    inline = [
      "sudo apt update -y",
      "sudo apt install -y python3 python3-pip python3-venv",
      "mkdir -p /home/ubuntu/flask_project",
      "mv /home/ubuntu/app.py /home/ubuntu/flask_project/",
      "cd /home/ubuntu/flask_project && python3 -m venv venv",
      "cd /home/ubuntu/flask_project && . venv/bin/activate && pip install flask",
      "cd /home/ubuntu/flask_project && nohup venv/bin/python app.py > app.log 2>&1 &"
    ]
  }

  #################################
  # Local Exec Provisioner (Logging)
  #################################
  provisioner "local-exec" {
    command = <<EOT
echo "----------------------------------------" >> output.log
echo "Terraform Apply Time: $(date)" >> output.log
echo "EC2 Instance ID: ${self.id}" >> output.log
echo "EC2 Public IP: ${self.public_ip}" >> output.log
echo "EC2 Private IP: ${self.private_ip}" >> output.log
echo "VPC ID: ${aws_vpc.my_vpc.id}" >> output.log
echo "Subnet ID: ${aws_subnet.my_vpc_subnet.id}" >> output.log
echo "Security Group ID: ${aws_security_group.my_vpc_sg.id}" >> output.log
echo "----------------------------------------" >> output.log
EOT
  }
}
