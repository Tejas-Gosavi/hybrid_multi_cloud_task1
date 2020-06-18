provider "aws" {
  region = "ap-south-1"
  profile = "mytejas"
}


resource "aws_security_group" "t1sg" {
  name        = "t1sg"
  description = "Allow HTTP and SSH to ec2"
  vpc_id      = "vpc-2feef347"

  ingress {
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "t1sg"
  }
}


resource "aws_instance" "t1os" {
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name = "mykey"
  security_groups = ["t1sg"]

  tags = {
    Name = "t1os"
  }
}


output "public_ip"{
  value=aws_instance.t1os.public_ip
}


resource "aws_ebs_volume" "t1ebs" {
  availability_zone = aws_instance.t1os.availability_zone
  size              = 1

  tags = {
    Name = "t1ebs"
  }
}


resource "aws_volume_attachment" "t1ebs_attach" {
  
  depends_on = [
       aws_ebs_volume.t1ebs,
   ]

  device_name = "/dev/xvdh"
  volume_id   = aws_ebs_volume.t1ebs.id
  instance_id = aws_instance.t1os.id
  force_detach = true
}


resource "null_resource" "null1" {

   depends_on = [
       aws_volume_attachment.t1ebs_attach,
   ]

   connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("C:/Users/HP/Downloads/mykey.pem")
    host     = aws_instance.t1os.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount /dev/xvdh   /var/www/html",
      "sudo rm -rf /var/www/html",
      "sudo git clone https://github.com/Tejas-Gosavi/task1.git /var/www/html"
    ]
   }
}


resource "aws_s3_bucket" "t1s3" {
  
  depends_on = [
       null_resource.null1,
   ]

  bucket = "myt1s3"
  acl    = "public-read"
  versioning {
          enabled = true
  }
  tags = {
    Name        = "myt1s3"
  }
}


locals {
  s3_origin_id = "S3-${aws_s3_bucket.t1s3.bucket}"
}


resource "aws_s3_bucket_object" "upload" {
   depends_on = [
       aws_s3_bucket.t1s3
   ]
  bucket = aws_s3_bucket.t1s3.bucket
  key    = "tejas.jpeg"
  source = ("C:/Users/HP/Desktop/terra/task1/tejas.jpeg")
  acl = "public-read"
  content_type = "image/jpeg"
}


resource "aws_cloudfront_distribution" "s3_distribution" {

  depends_on = [
       aws_s3_bucket_object.upload,
   ]

  origin {
    domain_name = aws_s3_bucket.t1s3.bucket_domain_name
    origin_id   = local.s3_origin_id
  }

  enabled             = true
  
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

    viewer_certificate {
    cloudfront_default_certificate = true
  }
}


resource "null_resource" "null2" {
   depends_on = [
   null_resource.null1,
   null_resource.null2,
   aws_cloudfront_distribution.s3_distribution,
   ]
   connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("C:/Users/HP/Downloads/mykey.pem")
    host     = aws_instance.t1os.public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "sudo su <<END",
      "echo \" Hey,Tejas Gosavi here!!! <img src='http://${aws_cloudfront_distribution.s3_distribution.domain_name}/${aws_s3_bucket_object.upload.key}' height='300' width='300'>\" >> /var/www/html/my.html",
      "END",
    ]
  }

    provisioner "local-exec" {    
      command = "start chrome http://${aws_instance.t1os.public_ip}/my.html"
   }
}