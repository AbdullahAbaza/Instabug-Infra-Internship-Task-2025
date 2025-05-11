# Sealed Secrets with MySQL Deployment Example

This repository demonstrates how to use Bitnami's Sealed Secrets controller with a MySQL deployment in Kubernetes. It includes a plan for implementing an automated re-encryption mechanism for SealedSecrets.

## Repository Structure

- `MySql-Deployment/`: Contains Kubernetes manifests for deploying MySQL and Adminer
  - `mysql-deployment.yaml`: MySQL deployment configuration
  - `mysql-service.yaml`: Service to expose MySQL
  - `mysql-sealed-secret.yaml`: Encrypted version of the MySQL secret
  - `adminer-deployment.yaml`: Adminer deployment for MySQL management
  - `adminer-service.yaml`: Service to expose Adminer

- `test_reencryption/`: Contains scripts for testing the re-encryption mechanism
  - `reencrypt.sh`: Main script for re-encrypting SealedSecrets
  - `setup_test_env.sh`: Script to set up a test environment
  - `simulate_key_rotation.sh`: Script to simulate key rotation
  - `verify_reencryption.sh`: Script to verify re-encryption success
  - `README.md`: Instructions for using the test scripts

- `Automating_re-encryption_of_SealedSecrets.md`: Detailed plan for implementing an automated re-encryption mechanism for SealedSecrets

## MySQL Deployment with Sealed Secrets

This example demonstrates how to deploy MySQL with sensitive information (passwords, database names, etc.) securely stored using Sealed Secrets.

### Prerequisites

- Kubernetes cluster
- kubectl configured to communicate with your cluster
- Sealed Secrets controller installed in your cluster
- kubeseal CLI tool installed

### Installation Steps

1. **Install the Sealed Secrets Controller** (if not already installed):

```bash
# Using Helm
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update
helm install sealed-secrets sealed-secrets/sealed-secrets -n kube-system
```

2. **Deploy the MySQL application with Sealed Secrets**:

```bash
# Apply the sealed secret
kubectl apply -f MySql-Deployment/mysql-sealed-secret.yaml

# Deploy MySQL
kubectl apply -f MySql-Deployment/mysql-deployment.yaml
kubectl apply -f MySql-Deployment/mysql-service.yaml

# Deploy Adminer (optional, for database management)
kubectl apply -f MySql-Deployment/adminer-deployment.yaml
kubectl apply -f MySql-Deployment/adminer-service.yaml
```

3. **Access the MySQL database**:

```bash
# Forward the MySQL service port
kubectl port-forward svc/mysql 3306:3306

# Or access through Adminer
kubectl port-forward svc/adminer 8080:8080
```

Then open your browser at http://localhost:8080 to access Adminer.

### Creating Your Own Sealed Secrets

If you want to create your own sealed secrets for MySQL:

1. Create a regular Kubernetes Secret YAML file:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mysql-secret
type: Opaque
data:
  MYSQL_ROOT_PASSWORD: "cGFzc3dvcmQxMjM="  # base64 encoded "password123"
  MYSQL_DATABASE: "bXlkYg=="  # base64 encoded "mydb"
  MYSQL_USER: "ZGItdXNlcg=="  # base64 encoded "db-user"
  MYSQL_PASSWORD: "cGFzc3dvcmQxMjM="  # base64 encoded "password123"
```

2. Seal it using kubeseal:

```bash
kubeseal --format yaml < mysql-secret.yaml > mysql-sealed-secret.yaml
```

3. Apply the sealed secret to your cluster:

```bash
kubectl apply -f mysql-sealed-secret.yaml
```

## Automating Re-encryption of SealedSecrets

The repository includes a detailed plan for implementing an automated re-encryption mechanism for SealedSecrets. This feature would extend the functionality of the kubeseal CLI tool to allow users to easily re-encrypt all SealedSecrets after a key rotation has occurred.

For more details, see the [Automating_re-encryption_of_SealedSecrets.md](Automating_re-encryption_of_SealedSecrets.md) document.

## Testing Re-encryption

The `test_reencryption/` directory contains scripts for testing the re-encryption mechanism described in the plan. These scripts allow you to:

1. Set up a test environment with a Kubernetes cluster and sealed-secrets controller
2. Create sample sealed secrets for testing
3. Simulate key rotation in the sealed-secrets controller
4. Re-encrypt sealed secrets with the new key
5. Verify that the re-encryption was successful

To use these scripts, follow the instructions in the [test_reencryption/README.md](test_reencryption/README.md) file.

**Note:** The test scripts are provided for demonstration purposes and should be used in a test environment only.

## Security Considerations

- Never commit raw Secret files to version control
- Only commit SealedSecret files to version control
- Regularly rotate your actual secrets (passwords, etc.)
- Consider implementing the automated re-encryption mechanism described in this repository

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.
