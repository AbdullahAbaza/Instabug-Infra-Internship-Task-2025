#!/bin/bash

# Script to verify that SealedSecrets were successfully re-encrypted
# This will check if the secrets can still be decrypted after key rotation

set -e

echo "Verifying SealedSecrets re-encryption..."

# Check if secrets still exist and are accessible
echo "Checking if secrets are still accessible..."

# Check secret1 in test-ns1
if kubectl get secret secret1 -n test-ns1 &> /dev/null; then
    echo "✅ Secret 'secret1' in namespace 'test-ns1' is accessible"

    # Verify the content
    USERNAME=$(kubectl get secret secret1 -n test-ns1 -o jsonpath='{.data.username}' | base64 --decode)
    PASSWORD=$(kubectl get secret secret1 -n test-ns1 -o jsonpath='{.data.password}' | base64 --decode)

    if [ "$USERNAME" = "admin" ] && [ "$PASSWORD" = "password123" ]; then
        echo "✅ Secret 'secret1' content is correct"
    else
        echo "❌ Secret 'secret1' content is incorrect"
        echo "Expected: username=admin, password=password123"
        echo "Got: username=$USERNAME, password=$PASSWORD"
    fi
else
    echo "❌ Secret 'secret1' in namespace 'test-ns1' is not accessible"
fi

# Check secret2 in test-ns1
if kubectl get secret secret2 -n test-ns1 &> /dev/null; then
    echo "✅ Secret 'secret2' in namespace 'test-ns1' is accessible"

    # Verify the content
    API_KEY=$(kubectl get secret secret2 -n test-ns1 -o jsonpath='{.data.api-key}' | base64 --decode)

    if [ "$API_KEY" = "abcdef123456" ]; then
        echo "✅ Secret 'secret2' content is correct"
    else
        echo "❌ Secret 'secret2' content is incorrect"
        echo "Expected: api-key=abcdef123456"
        echo "Got: api-key=$API_KEY"
    fi
else
    echo "❌ Secret 'secret2' in namespace 'test-ns1' is not accessible"
fi

# Check secret3 in test-ns2
if kubectl get secret secret3 -n test-ns2 &> /dev/null; then
    echo "✅ Secret 'secret3' in namespace 'test-ns2' is accessible"

    # Verify the content
    DB_URL=$(kubectl get secret secret3 -n test-ns2 -o jsonpath='{.data.database-url}' | base64 --decode)

    if [ "$DB_URL" = "mysql://user:pass@localhost:3306/db" ]; then
        echo "✅ Secret 'secret3' content is correct"
    else
        echo "❌ Secret 'secret3' content is incorrect"
        echo "Expected: database-url=mysql://user:pass@localhost:3306/db"
        echo "Got: database-url=$DB_URL"
    fi
else
    echo "❌ Secret 'secret3' in namespace 'test-ns2' is not accessible"
fi

# Check if we can create a new SealedSecret with the new key
echo "Testing if we can create a new SealedSecret with the new key..."

# Create a new test secret
cat <<EOF > new-test-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: new-test-secret
  namespace: test-ns1
type: Opaque
data:
  test-key: $(echo -n "test-value" | base64)
EOF

# Get the controller service name
echo "Getting sealed-secrets controller service name..."
CONTROLLER_NAME=$(kubectl get service -n kube-system -l app.kubernetes.io/name=sealed-secrets -o jsonpath="{.items[0].metadata.name}")
echo "Controller service name: $CONTROLLER_NAME"

# Check if new-public-key.pem exists, if not fetch the current public key
if [ ! -f "new-public-key.pem" ]; then
    echo "new-public-key.pem not found, fetching current public key..."
    kubeseal --controller-name=$CONTROLLER_NAME --controller-namespace=kube-system --fetch-cert > new-public-key.pem
fi

# Seal the secret with the public key
echo "Sealing secret with public key..."
kubeseal --controller-name=$CONTROLLER_NAME --controller-namespace=kube-system --cert new-public-key.pem -o yaml < new-test-secret.yaml > new-sealed-secret.yaml

# Apply the sealed secret
kubectl apply -f new-sealed-secret.yaml

# Check if the secret was created
if kubectl get secret new-test-secret -n test-ns1 &> /dev/null; then
    echo "✅ New secret 'new-test-secret' was successfully created with the new key"

    # Verify the content
    TEST_KEY=$(kubectl get secret new-test-secret -n test-ns1 -o jsonpath='{.data.test-key}' | base64 --decode)

    if [ "$TEST_KEY" = "test-value" ]; then
        echo "✅ New secret content is correct"
    else
        echo "❌ New secret content is incorrect"
        echo "Expected: test-key=test-value"
        echo "Got: test-key=$TEST_KEY"
    fi
else
    echo "❌ Failed to create new secret with the new key"
fi

echo "Verification complete!"
