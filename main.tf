provider "aws" {
  region = var.aws_region
}
################
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}
################

resource "aws_key_pair" "aws_keypair" {
  key_name   = "terraform_test"
  public_key = file(var.ssh_key_public)
}

resource "aws_vpc" "vpc" {
  cidr_block = var.aws_vpc_cidr

  tags = {
    Name = "terraform_test_vpc"
  }
}

resource "aws_internet_gateway" "terraform_gw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "Internet gateway for C10K"
  }
}

resource "aws_route_table" "route_table" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.terraform_gw.id
  }

  tags = {
    Name = "C10K route table"
  }
}

resource "aws_subnet" "subnet" {
  vpc_id     = aws_vpc.vpc.id
  cidr_block = aws_vpc.vpc.cidr_block

  # map_public_ip_on_launch = true
  tags = {
    Name = "terraform_test_subnet"
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet.id
  route_table_id = aws_route_table.route_table.id
}

resource "aws_security_group" "server_sg" {
  vpc_id = aws_vpc.vpc.id

  # SSH ingress access for provisioning
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow SSH access for provisioning"
  }

  ingress {
    from_port   = var.es-app-master_port
    to_port     = var.es-app-master_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow access to ES servers"
  }
   ingress {
    from_port   = var.es-app-master_http_port
    to_port     = var.es-app-master_http_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow access to ES servers"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#set a placement group for masters
resource "aws_placement_group" "es-app-master" {
  name     = "es-app-master"
  strategy = "partition"

   tags = {
    Name = "es-app-master-pg"
    Cluster ="app"
  }
}

resource "aws_instance" "es-app-master" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.server_instance_type
  subnet_id                   = aws_subnet.subnet.id
  vpc_security_group_ids      = [aws_security_group.server_sg.id]
  key_name                    = aws_key_pair.aws_keypair.key_name
  //placement_group             = "es-app-master"
  associate_public_ip_address = true
  count                       = 3

  tags = {
    Name = "es-app-master-${count.index + 1}"
    Cluster ="app"

  }

  provisioner "remote-exec" {
    # Install Python for Ansible
    inline = ["sudo apt update; sudo apt upgrade -y; sudo apt install ansible -y"]

    connection {
      host        = coalesce(self.public_ip, self.private_ip)
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(var.ssh_key_private)
    }
  }

  provisioner "local-exec" {
    command = "ansible-playbook -u ubuntu -i '${self.public_ip},' --private-key ${var.ssh_key_private} -T 300 provision.yml"
  }

  provisioner "local-exec" {
    command = "ansible-playbook -u ubuntu -i '${self.public_ip},' --private-key ${var.ssh_key_private} -T 300 site.yml"
  }
}

##################
#Make a resource with for_each and customize the host and command to reflect the iteration values



// resource "null_resource" "ansible" {
//   triggers = {
//     always_run = "${timestamp()}"
//   } 
//   count = length(aws_instance.es-app-master) 
 
//   provisioner "local-exec" {
//     command = "ansible-playbook -u ubuntu -i '${self.public_ip},' --private-key ${var.ssh_key_private} -T 300 site.yml"
//   }


// connection {
//     host        = coalesce(self.public_ip, self.private_ip)
//     type        = "ssh"
//     user        = "ubuntu"
//     private_key = file(var.ssh_key_private)
//   }

// }