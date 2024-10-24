############################################################### Loki ####################################################################
# Security Group for Loki
resource "aws_security_group" "loki" {
  name        = "Loki-SecurityGroup"
  description = "Security Group for Loki Server"
  vpc_id      = var.vpc_id

  ingress {
    from_port        = 3100
    to_port          = 3100
    protocol         = "tcp"
    cidr_blocks      = var.cidr_blocks
  }

  ingress {
    from_port        = 9096
    to_port          = 9096
    protocol         = "tcp"
    cidr_blocks      = ["10.10.0.0/16"]
  }
  
  ingress {
    from_port        = 9093
    to_port          = 9093
    protocol         = "tcp"
    cidr_blocks      = ["10.10.0.0/16"]
  }
  
  ingress {
    from_port        = 7946
    to_port          = 7946
    protocol         = "tcp"
    cidr_blocks      = ["10.10.0.0/16"]
  }

  ingress {
    from_port        = 9080
    to_port          = 9080
    protocol         = "tcp"
    cidr_blocks      = ["10.10.0.0/16"]
  }

  ingress {
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = var.cidr_blocks
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "loki-server-sg"
  }
}

# Security Group for Grafana Server
resource "aws_security_group" "grafana" {
  name        = "Grafana-SecurityGroup"
  description = "Security Group for Grafana Server"
  vpc_id      = var.vpc_id

  ingress {
    from_port        = 9080
    to_port          = 9080
    protocol         = "tcp"
    cidr_blocks      = ["10.10.0.0/16"]
  }

  ingress {
    from_port        = 3000
    to_port          = 3000
    protocol         = "tcp"
    security_groups  = [aws_security_group.grafana_alb.id]
  } 

  ingress {
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = var.cidr_blocks
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "grafana-server-sg"
  }
}

# Security Group for Application Server
resource "aws_security_group" "application" {
  name        = "ApplicationServer-SecurityGroup"
  description = "Security Group for Application Server"
  vpc_id      = var.vpc_id

  ingress {
    from_port        = 9080
    to_port          = 9080
    protocol         = "tcp"
    cidr_blocks      = ["10.10.0.0/16"]
  }

  ingress {
    from_port        = 3000
    to_port          = 3000
    protocol         = "tcp"
    cidr_blocks      = var.cidr_blocks
  }

  ingress {
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = var.cidr_blocks
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "application-server-sg"
  }
}

resource "aws_instance" "loki" {
  count         = 3
  ami           = var.provide_ami
  instance_type = var.instance_type
  monitoring = true
  vpc_security_group_ids = [aws_security_group.loki.id]      ### var.vpc_security_group_ids       ###[aws_security_group.all_traffic.id]
  subnet_id = var.subnet_id                                 ###aws_subnet.public_subnet[0].id
  root_block_device{
    volume_type="gp2"
    volume_size="20"
    encrypted=true
    kms_key_id = var.kms_key_id
    delete_on_termination=true
  }
  user_data = file("user_data_loki.sh")

  lifecycle{
    prevent_destroy=false
    ignore_changes=[ ami ]
  }

  private_dns_name_options {
    enable_resource_name_dns_a_record    = true
    enable_resource_name_dns_aaaa_record = false
    hostname_type                        = "ip-name"
  }

  metadata_options { #Enabling IMDSv2
    http_endpoint = "enabled"
    http_tokens   = "required"
    http_put_response_hop_limit = 2
  }

  tags={
    Name="${var.name}-Server-${count.index + 1}"
    Environment = var.env
  }
}

resource "aws_eip" "eip_associate_loki" {
  count  = 3
  domain = "vpc"     ###vpc = true
}
resource "aws_eip_association" "eip_association_loki" {  ### I will use this EC2 behind the ALB.
  count         = 3
  instance_id   = aws_instance.loki[count.index].id
  allocation_id = aws_eip.eip_associate_loki[count.index].id
}

############################################################# Grafana ###########################################################################

resource "aws_instance" "grafana" {
  ami           = var.provide_ami
  instance_type = var.instance_type
  monitoring = true
  vpc_security_group_ids = [aws_security_group.grafana.id]  ### var.vpc_security_group_ids       ###[aws_security_group.all_traffic.id]
  subnet_id = var.subnet_id                                 ###aws_subnet.public_subnet[0].id
  root_block_device{
    volume_type="gp2"
    volume_size="20"
    encrypted=true
    kms_key_id = var.kms_key_id
    delete_on_termination=true
  }
  user_data = file("user_data_grafana.sh")
  iam_instance_profile = "Administrator_Access"  # IAM Role to be attached to EC2

  lifecycle{
    prevent_destroy=false
    ignore_changes=[ ami ]
  }

  private_dns_name_options {
    enable_resource_name_dns_a_record    = true
    enable_resource_name_dns_aaaa_record = false
    hostname_type                        = "ip-name"
  }

  metadata_options { #Enabling IMDSv2
    http_endpoint = "enabled"
    http_tokens   = "required"
    http_put_response_hop_limit = 2
  }

  tags={
    Name="Grafana-Server"
    Environment = var.env
  }
}
resource "aws_eip" "eip_associate_grafana" {
  domain = "vpc"     ###vpc = true
}
resource "aws_eip_association" "eip_association_grafana" {  ### I will use this EC2 behind the ALB.
  instance_id   = aws_instance.grafana.id
  allocation_id = aws_eip.eip_associate_grafana.id
}

############################################################# Application Server ###########################################################################

resource "aws_instance" "app_server" {
  count         = 2
  ami           = var.provide_ami
  instance_type = var.instance_type
  monitoring = true
  vpc_security_group_ids = [aws_security_group.application.id]  ### var.vpc_security_group_ids       ###[aws_security_group.all_traffic.id]
  subnet_id = var.subnet_id                                 ###aws_subnet.public_subnet[0].id
  root_block_device{
    volume_type="gp2"
    volume_size="20"
    encrypted=true
    kms_key_id = var.kms_key_id
    delete_on_termination=true
  }
  user_data = file("user_data_application.sh")
#  iam_instance_profile = "Administrator_Access"  # IAM Role to be attached to EC2

  lifecycle{
    prevent_destroy=false
    ignore_changes=[ ami ]
  }

  private_dns_name_options {
    enable_resource_name_dns_a_record    = true
    enable_resource_name_dns_aaaa_record = false
    hostname_type                        = "ip-name"
  }

  metadata_options { #Enabling IMDSv2
    http_endpoint = "enabled"
    http_tokens   = "required"
    http_put_response_hop_limit = 2
  }

  tags={
    Name="app-Server-${count.index + 1}"
    Environment = var.env
  }
}
