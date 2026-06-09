resource "aws_iam_role" "codebuild" {
  name = "${var.project_name}-${var.environment}-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "codebuild" {
  name = "codebuild-policy"
  role = aws_iam_role.codebuild.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRAuth"
        Effect = "Allow"
        Action = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "ECRRepositories"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:CreateRepository",
          "ecr:DescribeRepositories"
        ]
        Resource = "arn:aws:ecr:${var.aws_region}:*:repository/*"
      },
      {
        Sid    = "Logs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3Cache"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.codebuild_cache.arn}/*"
      }
    ]
  })
}

resource "aws_s3_bucket" "codebuild_cache" {
  bucket        = "${var.project_name}-${var.environment}-codebuild-cache"
  force_destroy = true

  tags = {
    Name = "${var.project_name}-${var.environment}-codebuild-cache"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "codebuild_cache" {
  bucket = aws_s3_bucket.codebuild_cache.id

  rule {
    id     = "expire-cache"
    status = "Enabled"
    filter {}
    expiration {
      days = 7
    }
  }
}

resource "aws_codebuild_project" "build_images" {
  name          = "${var.project_name}-${var.environment}-build-images"
  description   = "Builds and pushes all 5 tier Docker images to ECR"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 30

  artifacts {
    type = "NO_ARTIFACTS"
  }

  cache {
    type     = "S3"
    location = aws_s3_bucket.codebuild_cache.bucket
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }
  }

  source {
    type            = "GITHUB"
    location        = var.github_repo_url
    git_clone_depth = 1
    buildspec       = "buildspec.yml"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-build-images"
  }
}

output "codebuild_project_name" {
  description = "CodeBuild project name — use this to trigger a build"
  value       = aws_codebuild_project.build_images.name
}

output "codebuild_start_command" {
  description = "AWS CLI command to trigger a build"
  value       = "aws codebuild start-build --project-name ${aws_codebuild_project.build_images.name} --region ${var.aws_region}"
}
