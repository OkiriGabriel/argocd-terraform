#!/bin/bash

# create-eks-cluster.sh

# Set variables
CLUSTER_NAME="argocd"
REGION="us-east-1"
NODE_GROUP_NAME="argocd"
NODE_TYPE="t2.medium"
NODE_COUNT="2"
EXISTING_EKS_ROLE_ARN="arn:aws:iam::147726474727:role/myeksrole"
EXISTING_WORKER_ROLE_ARN="arn:aws:iam::147726474727:role/workernode"
KUBERNETES_VERSION="1.31"  # Specify the desired Kubernetes version

# Create EKS cluster
echo "Creating EKS cluster..."
SUBNET_IDS=$(aws ec2 describe-subnets --region $REGION --query 'Subnets[].SubnetId' --output text | tr '\t' ',')

# Check if cluster already exists
if aws eks describe-cluster --name $CLUSTER_NAME --region $REGION > /dev/null 2>&1; then
  echo "EKS cluster '$CLUSTER_NAME' already exists. Skipping cluster creation."
else
  aws eks create-cluster \
      --name $CLUSTER_NAME \
      --region $REGION \
      --role-arn $EXISTING_EKS_ROLE_ARN \
      --kubernetes-version $KUBERNETES_VERSION \
      --resources-vpc-config subnetIds=$SUBNET_IDS,securityGroupIds=,endpointPublicAccess=true,endpointPrivateAccess=true
fi

# Wait for cluster to be created
echo "Waiting for cluster to be created..."
aws eks wait cluster-active \
    --name $CLUSTER_NAME \
    --region $REGION

# Create node group
echo "Creating node group..."
# Check if node group already exists
if aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NODE_GROUP_NAME --region $REGION > /dev/null 2>&1; then
  echo "EKS node group '$NODE_GROUP_NAME' already exists. Skipping node group creation."
else
  aws eks create-nodegroup \
      --cluster-name $CLUSTER_NAME \
      --nodegroup-name $NODE_GROUP_NAME \
      --node-role $EXISTING_WORKER_ROLE_ARN \
      --subnets $(aws ec2 describe-subnets --region $REGION --query 'Subnets[].SubnetId' --output text) \
      --instance-types $NODE_TYPE \
      --scaling-config minSize=2,maxSize=4,desiredSize=$NODE_COUNT \
      --disk-size 20 \
      --ami-type AL2_x86_64 \
      --capacity-type ON_DEMAND \
      --region $REGION
fi

echo "EKS cluster and node group creation process initiated."

# Update kubeconfig
echo "Updating kubeconfig..."
# aws eks get-token --cluster-name $CLUSTER_NAME --region $REGION | kubectl apply -f -
aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION

echo "Cluster info:"
kubectl cluster-info

echo "Nodes:"
kubectl get nodes

# Enable addons after cluster creation
echo "Enabling EKS addons..."
for addon in vpc-cni coredns kube-proxy; do
  if aws eks describe-addon --cluster-name $CLUSTER_NAME --addon-name $addon --region $REGION > /dev/null 2>&1; then
    echo "EKS addon '$addon' already exists. Skipping addon creation."
  else
    aws eks create-addon --cluster-name $CLUSTER_NAME --addon-name $addon --region $REGION
  fi
done

echo "EKS cluster creation and configuration complete."