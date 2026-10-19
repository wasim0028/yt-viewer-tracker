
locals {
  cluster_tag_key = "kubernetes.io/cluster/${var.cluster_name}"
}

resource "aws_vpc" "main" {
    cidr_block = var.cidr_block
    enable_dns_hostnames = true
    enable_dns_support = true
    tags = {
      Name = "${var.name}-vpc"
    }
}

resource "aws_subnet" "public" {
    vpc_id = aws_vpc.main.id
    for_each = {
        for idx, cidr in var.public_subnets : cidr =>{
            cidr = cidr
            az = var.azs[idx]
            num = idx + 1
        }
    }
    cidr_block = each.value.cidr
    availability_zone = each.value.az
    map_public_ip_on_launch = true
    tags = {
      Name = "${var.name}-public-subnet-${each.value.num}"
      "kubernetes.io/role/elb" = "1"
      (local.cluster_tag_key) = "shared"
    }
}

resource "aws_subnet" "private" {
    vpc_id = aws_vpc.main.id
    for_each = {
      for idx, cidr in var.private_subnets : cidr => {
        cidr = cidr
        az = var.azs[idx]
        num = idx + 1
      }
    }
    cidr_block = each.value.cidr
    availability_zone = each.value.az
    tags = {
      Name = "${var.name}-private-subnet-${each.value.num}"
      "kubernetes.io/role/internal-elb" = "1"
      (local.cluster_tag_key) = "shared"
    }
}

resource "aws_internet_gateway" "igw" {
    vpc_id = aws_vpc.main.id
    tags = {
      Name = "${var.name}-internet-gateway"
    }
}

resource "aws_eip" "eip" {
    count = 1
    domain = "vpc"
    tags = {
        Name = "${var.name}-eip"
    }
}

resource "aws_nat_gateway" "nat" {
    count = 1
    allocation_id = aws_eip.eip[0].id
    subnet_id = aws_subnet.public[var.public_subnets[0]].id
    depends_on = [ aws_internet_gateway.igw ]
    tags = {
      Name = "${var.name}-nat-gateway"
    }
}

resource "aws_route_table" "public" {
    vpc_id = aws_vpc.main.id
    tags = {
      Name = "${var.name}-rt-public"
    }
}

resource "aws_route_table" "private" {
    vpc_id = aws_vpc.main.id
    tags = {
      Name = "${var.name}-rt-private"
    }
}

resource "aws_route" "public_access" {
    gateway_id = aws_internet_gateway.igw.id
    destination_cidr_block = "0.0.0.0/0"
    route_table_id = aws_route_table.public.id
}

resource "aws_route" "private_access" {
    nat_gateway_id = aws_nat_gateway.nat[0].id
    destination_cidr_block = "0.0.0.0/0"
    route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "public" {
    for_each = aws_subnet.public
    subnet_id = each.value.id
    route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
    for_each = aws_subnet.private
    subnet_id = each.value.id
    route_table_id = aws_route_table.private.id
}

