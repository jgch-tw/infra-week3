# Create a new instance of the latest Ubuntu 14.04 on an
# t2.micro node with an AWS Tag naming it "HelloWorld"

provider "aws" {
  profile = "justin"
  region = "ap-southeast-1"
}

# is guild-vpc the reference? rather than hard coding a concrete vpc_id below
resource "aws_vpc" "guild-vpc" {
  cidr_block = "11.0.0.0/16" # 2 ^ 16 = 65536 addresses, i.e. 256 x 256, or the last two parts

  tags = {
    Name = "infra-101" # this is the name on aws
  }
} # one vpc cannot span across other availability regions

# each subnet will split up the vpc's cidr_block, you can create subnets in different availability zones
# aws reserves first 4 and last ip address in each subnet
resource "aws_subnet" "guild-subnet-public" {
  # vpc_id = "vpc-0516536067c5285cb" # hard coded, but changes when a new one is provisioned above!! so bad idea to hard code
  vpc_id = "${aws_vpc.guild-vpc.id}"
  cidr_block = "11.0.1.0/24" # 2 ^ 8 = 256 just uses the last part

  tags = {
    Name = "infra-101-public"
  }
}

resource "aws_subnet" "guild-subnet-private" {
  vpc_id = "${aws_vpc.guild-vpc.id}"
  cidr_block = "11.0.2.0/24"

  tags = {
    Name = "infra-101-private"
  }
}

resource "aws_internet_gateway" "guild-igw" {
  vpc_id = "${aws_vpc.guild-vpc.id}"

  tags = {
    Name = "infra-101-igw"
  }
}

# every vpc comes with a "main" route table, which can be used to forward the public subnets
# https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Scenario2.html#VPC_Scenario2_Routing
# each route table must be associated with the public/private subnets

# 1 subnet to 1 route table
# 1 route table can have many subnets
# IF NO ROUTE TABLE IS ASSOCIATE WITH SUBNET, THE MAIN DEFAULT ROUTE TABLE WILL BE USED!!

# need to make this route table "public" by associating it with an internet gateway
resource "aws_route_table" "guild-route-table-public" {
  vpc_id = "${aws_vpc.guild-vpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.guild-igw.id}"
  }

  tags = {
    Name = "infra-101-route-table-public"
  }
}

resource "aws_route_table_association" "guild-association-public" {
  subnet_id = "${aws_subnet.guild-subnet-public.id}"
  route_table_id = "${aws_route_table.guild-route-table-public.id}"
}


# NAT gateway helps your vpc to talk to stuff outside in the internet and gives it a sort of front facing "ip"?
# so that stuff outside can reply, BUT stuff outside CANNOT request stuff in your private subnet!
# it's a Forward Proxy

# a NAT needs to be created with an assigned Elastic IP address
# in the gui there's a subnet_id but Terraform doesn't have it, we
# need a layer of indirection for aws_network_interface

/*
resource "aws_network_interface" "guild-private-subnet-multi-ip" {
  subnet_id = "${aws_subnet.guild-subnet-private.id}"
  # private_ips = ["10.0.0.10", "10.0.0.11"] # presumably for the instances that need internet access
}
*/

# nat gateway must always be in the public subnet, and depends on the internet gateway!
# https://blog.kaliloudiaby.com/index.php/terraform-to-provision-vpc-on-aws-amazon-web-services/
resource "aws_eip" "guild-eip-nat" {
  vpc = true
  # network_interface = "${aws_network_interface.guild-private-subnet-multi-ip.id}" # Do not use network_interface to associate the EIP to aws_lb or aws_nat_gateway resources.
  depends_on = ["aws_internet_gateway.guild-igw"]

  tags = {
    Name = "infra-101-eip-nat"
  }
}

# nat gateway must always be in the public subnet
resource "aws_nat_gateway" "guild-ngw" {
  allocation_id = "${aws_eip.guild-eip-nat.id}"
  subnet_id = "${aws_subnet.guild-subnet-public.id}"

  tags = {
    Name = "infra-101-ngw"
  }
}

resource "aws_route_table" "guild-route-table-private" {
  vpc_id = "${aws_vpc.guild-vpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_nat_gateway.guild-ngw.id}"
  }

  tags = {
    Name = "infra-101-route-table-private"
  }
}

resource "aws_route_table_association" "guild-association-private" {
  subnet_id = "${aws_subnet.guild-subnet-private.id}"
  route_table_id = "${aws_route_table.guild-route-table-private.id}"
}

resource "aws_security_group" "guild-security-group" {
  vpc_id = "${aws_vpc.guild-vpc.id}"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["128.106.1.171/32"] # tw office IP
  }

  ingress {
    from_port = 8080
    to_port = 8080
    protocol = "tcp"
    cidr_blocks = ["11.0.0.0/16"]
  }
}

resource "aws_instance" "infra-101-ec2" {
  ami           = "ami-00942d7cd4f3ca5c0"
  instance_type = "t2.micro"
  user_data = "${file("main.sh")}"

  vpc_security_group_ids = [aws_security_group.guild-security-group.id]
  subnet_id = "${aws_subnet.guild-subnet-private.id}"
  tags = {
    Name = "infra-101-ec2"
  }
}
