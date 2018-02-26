variable "region" {}

variable "availability_zone" {}

variable "environment" {
  default = "Production"
}

variable "cidr_block" {
  default = "10.0.1.0/24"
}

variable "ami_tag" {
  default = "2018-02-07"
}

variable "ec2_role" {
  default = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      }
    }
  ]
}
EOF
}

provider "aws" {
  version                 = "~> 1.8"
  shared_credentials_file = "../credentials/root.awscreds"
  profile                 = "default"
  region                  = "${var.region}"
}

///

data "aws_vpc" "main" {
  tags {
    Name  = "Batman"
    Owner = "Infrastructure"
  }
}

data "aws_security_group" "default" {
  vpc_id = "${data.aws_vpc.main.id}"

  filter = [
    {
      name   = "group-name"
      values = ["default"]
    },
  ]
}

data "aws_security_group" "ssh" {
  vpc_id = "${data.aws_vpc.main.id}"
  name   = "ssh"
}

resource "aws_subnet" "main" {
  vpc_id            = "${data.aws_vpc.main.id}"
  availability_zone = "${var.availability_zone}"
  cidr_block        = "${var.cidr_block}"

  tags {
    Name        = "Batman ${var.environment}"
    Environment = "${var.environment}"
    Owner       = "Infrastructure"
  }
}

resource "aws_key_pair" "batman" {
  key_name   = "batman-${lower(var.environment)}-key"
  public_key = "${file("../keys/batman.pubkey")}"
}

///

data "aws_ami" "controller-ami" {
  filter {
    name   = "name"
    values = ["batman-build-${var.ami_tag}"]
  }
}

resource "aws_instance" "controller" {
  subnet_id                   = "${aws_subnet.main.id}"
  instance_type               = "t2.small"
  ami                         = "${data.aws_ami.controller-ami.id}"
  vpc_security_group_ids      = ["${data.aws_security_group.default.id}", "${data.aws_security_group.ssh.id}"]
  key_name                    = "batman-${lower(var.environment)}-key"
  associate_public_ip_address = true
  iam_instance_profile        = "${aws_iam_instance_profile.controller.name}"

  tags {
    Name        = "Batman ${var.environment} Controller"
    Environment = "${var.environment}"
    Owner       = "Infrastructure"
  }
}

resource "aws_iam_instance_profile" "controller" {
  name = "batman-${lower(var.environment)}-controller"
  role = "${aws_iam_role.controller.name}"
}

resource "aws_iam_role" "controller" {
  name = "batman-${lower(var.environment)}-controller"

  assume_role_policy = "${var.ec2_role}"
}

resource "aws_iam_role_policy_attachment" "controller-policy-autoscaling" {
  role       = "${aws_iam_role.controller.name}"
  policy_arn = "arn:aws:iam::aws:policy/AutoScalingFullAccess"
}

resource "aws_iam_role_policy_attachment" "controller-policy-ec2" {
  role       = "${aws_iam_role.controller.name}"
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

resource "aws_iam_role_policy_attachment" "controller-policy-ecr" {
  role       = "${aws_iam_role.controller.name}"
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
}

resource "aws_ebs_volume" "build-cache" {
  availability_zone = "${aws_subnet.main.availability_zone}"
  size              = 500

  tags {
    Name        = "Batman ${var.environment} Build Cache"
    Environment = "${var.environment}"
    Owner       = "Infrastructure"
  }
}

resource "aws_volume_attachment" "build-cache-attachment" {
  instance_id = "${aws_instance.controller.id}"
  volume_id   = "${aws_ebs_volume.build-cache.id}"
  device_name = "/dev/sdx"

  skip_destroy = true

  provisioner "local-exec" {
    command = "./on-host ubuntu@${aws_instance.controller.public_dns} ./initialize-cache /dev/xvdx"
  }
}

output "controller-host" {
  value = "${aws_instance.controller.public_dns}"
}

///

data "aws_ami" "worker-ami" {
  filter {
    name   = "name"
    values = ["batman-worker-${var.ami_tag}"]
  }
}

resource "aws_launch_configuration" "worker-configuration" {
  name                        = "batman-${lower(var.environment)}-worker"
  instance_type               = "g2.2xlarge"
  image_id                    = "${data.aws_ami.worker-ami.id}"
  security_groups             = ["${data.aws_security_group.default.id}", "${data.aws_security_group.ssh.id}"]
  key_name                    = "batman-${lower(var.environment)}-key"
  associate_public_ip_address = true
  iam_instance_profile        = "${aws_iam_instance_profile.worker.name}"

  spot_price = "1"

  ebs_block_device {
    volume_size = 100
    device_name = "/dev/sdx"
  }

  user_data = "${replace(file("initialize-cache"), "$1", "/dev/xvdx")}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "worker" {
  name                 = "batman-${lower(var.environment)}-worker"
  vpc_zone_identifier  = ["${aws_subnet.main.id}"]
  availability_zones   = ["${var.availability_zone}"]
  launch_configuration = "${aws_launch_configuration.worker-configuration.name}"

  min_size         = 0
  max_size         = 50
  desired_capacity = 0

  lifecycle {
    ignore_changes = ["min_size", "desired_capacity"]
  }

  tags = [
    {
      key                 = "Name"
      value               = "Batman ${var.environment} Worker"
      propagate_at_launch = true
    },
    {
      key                 = "Environment"
      value               = "${var.environment}"
      propagate_at_launch = true
    },
    {
      key                 = "Owner"
      value               = "Infrastructure"
      propagate_at_launch = true
    },
    {
      key                 = "Execution-Id"
      value               = ""
      propagate_at_launch = true
    },
  ]
}

resource "aws_iam_instance_profile" "worker" {
  name = "batman-${lower(var.environment)}-worker"
  role = "${aws_iam_role.worker.name}"
}

resource "aws_iam_role" "worker" {
  name = "batman-${lower(var.environment)}-worker"

  assume_role_policy = "${var.ec2_role}"
}

resource "aws_iam_role_policy_attachment" "worker-policy-ecr" {
  role       = "${aws_iam_role.worker.name}"
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

output "autoscaling-group-name" {
  value = "${aws_autoscaling_group.worker.name}"
}
