#!/bin/bash

# Script to set up a test environment for SealedSecrets re-encryption
# This will create a Minikube cluster, install the sealed-secrets controller,
# and create some sample SealedSecrets for testing

set -e

echo "Setting up test environment for SealedSecrets re-encryption..."

# Check if minikube is installed
if ! command -v minikube &> /dev/null; then
    echo "Error: minikube is not installed. Please install it first."
    exit 1
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not installed. Please install it first."
    exit 1
fi

# Check if helm is installed
if ! command -v helm &> /dev/null; then
    echo "Error: helm is not installed. Please install it first."
    exit 1
fi

# Check if kubeseal is installed
if ! command -v kubeseal &> /dev/null; then
    echo "Error: kubeseal is not installed. Please install it first."
    exit 1
fi

# Start minikube if it's not running
if ! minikube status | grep -q "Running"; then
    echo "Starting minikube..."
    minikube start
fi

# # Add the sealed-secrets Helm repository
# echo "Adding sealed-secrets Helm repository..."
# helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
# helm repo update

# # Install the sealed-secrets controller
# echo "Installing sealed-secrets controller..."
# helm install sealed-secrets sealed-secrets/sealed-secrets -n kube-system

# Wait for the controller to be ready
echo "Waiting for sealed-secrets controller to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/sealed-secrets -n kube-system

# Get the controller service name
echo "Getting sealed-secrets controller service name..."
CONTROLLER_NAME=$(kubectl get service -n kube-system -l app.kubernetes.io/name=sealed-secrets -o jsonpath="{.items[0].metadata.name}")
echo "Controller service name: $CONTROLLER_NAME"

# Create test namespaces
echo "Creating test namespaces..."
kubectl create namespace test-ns1 --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace test-ns2 --dry-run=client -o yaml | kubectl apply -f -

# Fetch the public key
echo "Fetching public key from sealed-secrets controller..."
kubeseal --controller-name=$CONTROLLER_NAME --controller-namespace=kube-system --fetch-cert > public-key.pem

# Create sample secrets and seal them
echo "Creating sample secrets and sealing them..."

# Secret 1 in test-ns1
cat <<EOF > secret1.yaml
apiVersion: v1
kind: Secret
metadata:
  name: secret1
  namespace: test-ns1
type: Opaque
data:
  username: $(echo -n "admin" | base64)
  password: $(echo -n "password123" | base64)
EOF

# Secret 2 in test-ns1
cat <<EOF > secret2.yaml
apiVersion: v1
kind: Secret
metadata:
  name: secret2
  namespace: test-ns1
type: Opaque
data:
  api-key: $(echo -n "abcdef123456" | base64)
EOF

# Secret 3 in test-ns2
cat <<EOF > secret3.yaml
apiVersion: v1
kind: Secret
metadata:
  name: secret3
  namespace: test-ns2
type: Opaque
data:
  database-url: $(echo -n "mysql://user:pass@localhost:3306/db" | base64)
EOF

# Seal the secrets
echo "Sealing secrets..."
kubeseal --cert public-key.pem -o yaml < secret1.yaml > sealed-secret1.yaml
kubeseal --cert public-key.pem -o yaml < secret2.yaml > sealed-secret2.yaml
kubeseal --cert public-key.pem -o yaml < secret3.yaml > sealed-secret3.yaml

# Apply the sealed secrets
echo "Applying sealed secrets to the cluster..."
kubectl apply -f sealed-secret1.yaml
kubectl apply -f sealed-secret2.yaml
kubectl apply -f sealed-secret3.yaml

# Verify that the secrets were created
echo "Verifying that secrets were created..."
kubectl get secrets -n test-ns1
kubectl get secrets -n test-ns2

echo "Test environment setup complete!"
echo "You can now test the re-encryption script with:"
echo "./reencrypt.sh --all-namespaces"
