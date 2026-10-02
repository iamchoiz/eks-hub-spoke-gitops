output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  value = [for s in aws_subnet.public : s.id]
}

output "controlplane_subnet_ids" {
  value = [for s in aws_subnet.controlplane : s.id]
}

output "node_subnet_ids" {
  value = [for s in aws_subnet.node : s.id]
}

output "pod_subnet_ids" {
  value = [for s in aws_subnet.pod : s.id]
}
