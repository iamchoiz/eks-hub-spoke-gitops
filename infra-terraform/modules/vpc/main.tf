resource "aws_vpc" "this" {
  cidr_block = var.cidr
  tags       = var.vpc_tags

  enable_dns_support   = true
  enable_dns_hostnames = true

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_vpc_ipv4_cidr_block_association" "pod_secondary" {
  vpc_id     = aws_vpc.this.id
  cidr_block = var.pod_secondary_cidr
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = var.internet_gateway_tags
}

resource "aws_subnet" "public" {
  for_each = var.public_subnets

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value.cidr
  tags              = each.value.tags
}

resource "aws_subnet" "controlplane" {
  for_each = var.controlplane_subnets

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value.cidr
  tags              = each.value.tags
}

resource "aws_subnet" "node" {
  for_each = var.node_subnets

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value.cidr
  tags              = each.value.tags
}

resource "aws_subnet" "pod" {
  for_each = var.pod_subnets

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value.cidr
  tags              = each.value.tags

  depends_on = [aws_vpc_ipv4_cidr_block_association.pod_secondary]
}

resource "aws_eip" "nat" {
  for_each = var.nat_gateways

  domain = "vpc"
  tags   = each.value.eip_tags
}

resource "aws_nat_gateway" "this" {
  for_each = var.nat_gateways

  subnet_id     = aws_subnet.public[each.key].id
  allocation_id = aws_eip.nat[each.key].id
  tags          = each.value.tags

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = var.public_route_table_tags
}

resource "aws_route" "public_igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = var.default_route_cidr
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  for_each = var.private_route_tables

  vpc_id = aws_vpc.this.id
  tags   = each.value.tags
}

resource "aws_route" "private_nat" {
  for_each = var.private_route_tables

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = var.default_route_cidr
  nat_gateway_id         = aws_nat_gateway.this[each.value.nat_az].id
}

resource "aws_route_table_association" "node" {
  for_each = aws_subnet.node

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

resource "aws_route_table_association" "controlplane" {
  for_each = aws_subnet.controlplane

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

resource "aws_route_table_association" "pod" {
  for_each = aws_subnet.pod

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = var.s3_endpoint_service_name
  vpc_endpoint_type = "Gateway"
  tags              = var.s3_endpoint_tags

  route_table_ids = [for rt in aws_route_table.private : rt.id]
}

resource "aws_security_group" "endpoints" {
  name_prefix = var.endpoints_security_group_name_prefix
  description = var.endpoints_security_group_description
  vpc_id      = aws_vpc.this.id
  tags        = var.endpoints_security_group_tags

  ingress {
    description = var.endpoints_ingress_description
    from_port   = var.endpoints_ingress_port
    to_port     = var.endpoints_ingress_port
    protocol    = var.endpoints_ingress_protocol
    cidr_blocks = var.endpoints_ingress_cidrs
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = var.interface_endpoints

  vpc_id              = aws_vpc.this.id
  service_name        = each.value.service_name
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  tags                = each.value.tags

  subnet_ids         = [for s in aws_subnet.node : s.id]
  security_group_ids = [aws_security_group.endpoints.id]
}
