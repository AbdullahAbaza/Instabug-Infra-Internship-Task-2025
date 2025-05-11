#!/bin/bash

# Script to simulate key rotation in the sealed-secrets controller
# This will backup the current keys, delete them to trigger key rotation,
# and then verify that new keys were generated

set -e

echo "Simulating key rotation for sealed-secrets controller..."

# Backup existing keys
echo "Backing up existing sealed-secrets keys..."
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > sealed-secrets-keys-backup.yaml

# Count the number of keys before rotation
KEY_COUNT_BEFORE=$(kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key | grep -v NAME | wc -l)
echo "Number of keys before rotation: $KEY_COUNT_BEFORE"

# Delete the secrets to trigger key rotation
echo "Deleting sealed-secrets keys to trigger rotation..."
kubectl delete secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key

# Restart the controller to trigger key generation
echo "Restarting the sealed-secrets controller to trigger key generation..."
CONTROLLER_POD=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets -o jsonpath="{.items[0].metadata.name}")
echo "Controller pod: $CONTROLLER_POD"
kubectl delete pod -n kube-system $CONTROLLER_POD

# Wait for the controller to restart and generate a new key
echo "Waiting for controller to restart and generate new keys..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=sealed-secrets -n kube-system --timeout=60s
sleep 10  # Additional time for key generation after pod is ready

# Verify that new keys were generated
KEY_COUNT_AFTER=$(kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key | grep -v NAME | wc -l)
echo "Number of keys after rotation: $KEY_COUNT_AFTER"

if [ "$KEY_COUNT_AFTER" -gt 0 ]; then
    echo "Key rotation successful!"
    echo "New public key will be different from the old one."
    echo "You can now test the re-encryption script to update all SealedSecrets with the new key."
else
    echo "Error: No new keys were generated after rotation."
    echo "Restoring backup of original keys..."
    kubectl apply -f sealed-secrets-keys-backup.yaml
    exit 1
fi

# Get the controller service name
echo "Getting sealed-secrets controller service name..."
CONTROLLER_NAME=$(kubectl get service -n kube-system -l app.kubernetes.io/name=sealed-secrets -o jsonpath="{.items[0].metadata.name}")
echo "Controller service name: $CONTROLLER_NAME"

# Fetch the new public key
echo "Fetching new public key..."
kubeseal --controller-name=$CONTROLLER_NAME --controller-namespace=kube-system --fetch-cert > new-public-key.pem

echo "Key rotation simulation complete!"
