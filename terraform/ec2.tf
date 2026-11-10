# Última AMI de Amazon Linux 2023 (AWS la publica en este parámetro)
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "app" {
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private[0].id
  vpc_security_group_ids      = [aws_security_group.app.id]
  iam_instance_profile        = aws_iam_instance_profile.app.name
  associate_public_ip_address = false
  user_data_replace_on_change = true

  # IMDSv2 obligatorio: protege las credenciales del rol ante ataques SSRF
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
  }

  user_data = <<-EOF
    #!/bin/bash
    dnf install -y nginx
    echo "<h1>AWS Secure Cloud Infrastructure</h1><p>Servidor: $(hostname)</p>" > /usr/share/nginx/html/index.html
    systemctl enable --now nginx
  EOF

  # Esperar a que la salida a internet por el NAT esté lista
  depends_on = [
    aws_nat_gateway.nat,
    aws_route_table_association.private,
  ]

  tags = { Name = "secure-app" }
}