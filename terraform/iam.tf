# Quién puede usar el rol: el servicio EC2
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "secure-app-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
  tags               = { Name = "secure-app-role" }
}

# Único permiso: acceso por Session Manager (sin SSH)
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# El EC2 no usa el rol directo, usa un "instance profile" que lo contiene
resource "aws_iam_instance_profile" "app" {
  name = "secure-app-profile"
  role = aws_iam_role.app.name
}