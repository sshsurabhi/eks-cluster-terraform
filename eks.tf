# IAM role for EKS cluster
resource "aws_iam_role" "eks_cluster_role" {
  name = "eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })
}

# IAM Role Policy Attachments for EKS Cluster Role
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_iam_role_policy_attachment" "eks_service_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

# EKS Cluster
resource "aws_eks_cluster" "eks_cluster" {
  name     = "eks-cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    # Use private subnets for enhanced security
    subnet_ids         = [aws_subnet.private_1.id, aws_subnet.private_2.id]
    security_group_ids = [aws_security_group.eks_cluster_sg.id]
  }

  # Enable logging for the control plane
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = {
    Name        = "eks-cluster"
    Environment = "production"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_service_policy,
  ]
}

# Node Group for EKS Worker Nodes
resource "aws_eks_node_group" "eks_nodes" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = "eks-nodes"
  node_role_arn   = aws_iam_role.eks_node_role.arn

  # Use private subnets for worker nodes
  subnet_ids = [aws_subnet.private_1.id, aws_subnet.private_2.id]

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  instance_types = ["t3.medium"]

  # Optional SSH access to worker nodes
  remote_access {
    ec2_ssh_key = "my-ssh-key"  # Replace with your EC2 SSH key
  }

  tags = {
    Name        = "eks-nodes"
    Environment = "production"
  }
}

# IAM Role for EKS Worker Nodes
resource "aws_iam_role" "eks_node_role" {
  name = "eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

# Attach IAM Policies to the EKS Node Role
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_ecr_readonly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_role.name
}

# Optional policy for AWS Systems Manager (SSM) if you want SSM management
resource "aws_iam_role_policy_attachment" "ssm_managed_instance_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.eks_node_role.name
}


resource "aws_security_group" "eks_cluster_sg" {
  vpc_id = aws_vpc.main.id
  
  ingress {
    description     = "Allow worker nodes to communicate with control plane"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    cidr_blocks     = [aws_vpc.main.cidr_block]  # Restrict access to VPC CIDR
  }

  ingress {
    description     = "Allow communication between nodes and control plane"
    from_port       = 10250
    to_port         = 10250
    protocol        = "tcp"
    cidr_blocks     = [aws_vpc.main.cidr_block]  # Restrict access to VPC CIDR
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "eks-cluster-sg"
    Environment = "production"
  }
}

resource "kubernetes_namespace" "staging" {
  metadata {
    name = "staging"
    annotations = {
      "app.kubernetes.io/managed-by" = "Helm"
      "meta.helm.sh/release-name" = "petclinic"
      "meta.helm.sh/release-namespace" = "staging"
    }
  }
}


resource "helm_release" "petclinic" {
  name       = "petclinic"
  chart      = "/home/ubuntu/eks-cluster-terraform/Helm-Chart-Practice-K8S"
  #namespace  = "staging"

  values = [
    file("/home/ubuntu/eks-cluster-terraform/Helm-Chart-Practice-K8S/staging-values.yaml")
  ]

  timeout = 600
  wait    = true

  provisioner "local-exec" {
    command = "kubectl annotate namespace staging meta.helm.sh/release-name=petclinic --overwrite"
  }

  provisioner "local-exec" {
    command = "kubectl annotate namespace staging meta.helm.sh/release-namespace=staging --overwrite"
  }

  provisioner "local-exec" {
    command = "kubectl annotate namespace staging app.kubernetes.io/managed-by=Helm --overwrite"
  }

  depends_on = [kubernetes_namespace.staging]
}