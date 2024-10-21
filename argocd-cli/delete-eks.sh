#!/bin/bash

# Set variables
CLUSTER_NAME="argocd"
REGION="us-east-1"
NODE_GROUP_NAME="argocd"

# Delete the node group
echo "Deleting the EKS node group..."
aws eks delete-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NODE_GROUP_NAME --region $REGION

# Wait for the node group to be deleted
echo "Waiting for the node group to be deleted..."
while aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NODE_GROUP_NAME --region $REGION > /dev/null 2>&1; do
  sleep 5
done

echo "Node group deleted."

# Delete the cluster
echo "Deleting the EKS cluster..."
aws eks delete-cluster --name $CLUSTER_NAME --region $REGION

# Wait for the cluster to be deleted
echo "Waiting for the cluster to be deleted..."
while aws eks describe-cluster --name $CLUSTER_NAME --region $REGION > /dev/null 2>&1; do
  sleep 5
done

echo "Cluster deleted."

echo "EKS cluster and node group deletion complete."