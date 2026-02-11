provider "aws" {
    region = "eu-west-1"
}

resource "aws_vpc" "main_vpc" {
    cidr_block           = "10.0.0.0/16" # VPC with a /16 CIDR block (65,536 IP addresses)
    enable_dns_support   = true
    enable_dns_hostnames = true

    tags = {
        Name = "SecLab-VPC"
    }
}

#Public Subnet (for internet-facing resources)
resource "aws_subnet" "public_subnet" {
    vpc_id                 = aws_vpc.main_vpc.id
    cidr_block             = "10.0.1.0/24" # Public subnet with a /24 CIDR block (256 IP addresses)
    map_public_ip_on_launch = true # Automatically assign public IPs to instances launched in this subnet (for internet access)
    availability_zone      = "eu-west-1a"

    tags = {
        Name = "SecLab-Public-Subnet"
    }
}

#Private Subnet (for internal resources)
resource "aws_subnet" "private_subnet" {
    vpc_id            = aws_vpc.main_vpc.id
    cidr_block        = "10.0.2.0/24" # Private subnet with a /24 CIDR block (256 IP addresses)
    availability_zone = "eu-west-1a"

    tags = {
        Name = "SecLab-Private-Subnet"
    }
}

#Internet Gateway (to allow internet access for public subnet)
resource "aws_internet_gateway" "igw" {
    vpc_id = aws_vpc.main_vpc.id

    tags = {
        Name = "SecLab-IGW"
    }
}

#Route Table for Public Subnet
resource "aws_route_table" "public_rt" {
    vpc_id = aws_vpc.main_vpc.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.igw.id
    }

    tags = {
        Name = "SecLab-Public-RT"
    }
}

#Associate the Route Table with the Public Subnet
# This ensures that instances in the public subnet can access the internet (without this, they won't have a route to the internet)
resource "aws_route_table_association" "public_rt_assoc" {
    subnet_id      = aws_subnet.public_subnet.id
    route_table_id = aws_route_table.public_rt.id
}

#Create security group for public subnet (allow inbound HTTP and SSH)
resource "aws_security_group" "web_sg" {
    name        = "allow_web_traffic"
    description = "Allow inbound HTTP and SSH traffic"
    vpc_id      = aws_vpc.main_vpc.id

    #Inbound rules: Allow SSH (Port 22)
    ingress {
        description = "SSH from my IP only"
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = ["41.184.226.146/32"] #Adding /32 to specify a single IP address
    }

    #Inbound rules: Allow HTTP (Port 80)
    ingress {
        description = "HTTP from anywhere"
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    #Outbound rules: Allow all outbound traffic
    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1" # -1 means all protocols
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "SecLab-Web-SG"
    }
}

#Register keys with AWS
resource "aws_key_pair" "deployer" {
    key_name   = "seclab-key"
    public_key = file("./seclab-key.pub")
}

#Create an EC2 instance in the public subnet
resource "aws_instance" "web_server" {
    ami           = "ami-0f27749973e2399b6" #Ubuntu 22.04 LTS in eu-west-1
    instance_type = "t2.micro" 

    #Place the instance in the public subnet
    subnet_id                   = aws_subnet.public_subnet.id
    vpc_security_group_ids      = [aws_security_group.web_sg.id]     #Associate the security group with the instance
    associate_public_ip_address = true
    key_name                    = aws_key_pair.deployer.key_name     #Use the key pair we registered earlier

# Use user_data to install a web server on launch (this script runs when the instance starts)
    user_data = <<-EOF
                #!/bin/bash
                sudo apt update -y
                sudo apt install -y nginx
                echo "<h1>Deployed via Terraform - CyberKyrian Cloud Sec Lab</h1>" > /var/www/html/index.html
                sudo systemctl start nginx
                EOF

    tags = {
        Name = "SecLab-Web-Server"
    }
}

#Output the public IP of the web server
output "web_server_public_ip" {
    value = aws_instance.web_server.public_ip
} 