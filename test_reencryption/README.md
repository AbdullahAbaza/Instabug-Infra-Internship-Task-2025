# SealedSecrets Re-encryption Test Environment

This directory contains scripts to test the SealedSecrets re-encryption mechanism described in the main document.

## Prerequisites

Before running these tests, you need to have the following tools installed:

- [Minikube](https://minikube.sigs.k8s.io/docs/start/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/)
- [kubeseal](https://github.com/bitnami-labs/sealed-secrets#installation)
- [jq](https://stedolan.github.io/jq/download/)

## Test Scripts

The following scripts are provided:

1. `setup_test_env.sh`: Sets up a test environment with Minikube, installs the sealed-secrets controller, and creates sample SealedSecrets.
2. `simulate_key_rotation.sh`: Simulates key rotation in the sealed-secrets controller.
3. `reencrypt.sh`: The main script that implements the re-encryption mechanism.
4. `verify_reencryption.sh`: Verifies that the re-encryption was successful.

## Testing Process

Follow these steps to test the re-encryption mechanism:

### 1. Set up the test environment

```bash
./setup_test_env.sh
```

This will:
- Start Minikube (if not already running)
- Install the sealed-secrets controller
- Create test namespaces
- Create and apply sample SealedSecrets

### 2. Simulate key rotation

```bash
./simulate_key_rotation.sh
```

This will:
- Backup the current keys
- Delete the keys to trigger key rotation
- Restart the controller pod to ensure new keys are generated
- Verify that new keys were generated
- Fetch the new public key

### 3. Run the re-encryption script

```bash
./reencrypt.sh --all-namespaces
```

This will:
- List all SealedSecrets in the cluster
- Fetch the latest public key
- Re-encrypt each SealedSecret with the latest key
- Update the SealedSecret objects in the cluster

### 4. Verify the re-encryption

```bash
./verify_reencryption.sh
```

This will:
- Check if the secrets are still accessible
- Verify that the secret content is correct
- Test creating a new SealedSecret with the new key

## Important Implementation Notes

During our testing, we discovered several important considerations that have been incorporated into the scripts:

1. **Controller Service Discovery**: The sealed-secrets controller service name needs to be dynamically discovered rather than hardcoded. All scripts now use `kubectl get service -n kube-system -l app.kubernetes.io/name=sealed-secrets` to find the correct service.

2. **Key Rotation Mechanism**: Simply deleting the keys may not be enough to trigger key rotation. The `simulate_key_rotation.sh` script now also restarts the controller pod to ensure new keys are generated.

3. **Output Handling**: When listing SealedSecrets, it's important to properly capture and filter the output to avoid mixing log messages with the actual list of SealedSecrets. The `reencrypt.sh` script now uses proper output capture and filtering.

4. **Format Validation**: Before processing a SealedSecret, it's important to validate that it has the correct format (namespace/name). The `reencrypt.sh` script now includes format validation to prevent errors.

5. **Error Handling**: Robust error handling is essential for a reliable re-encryption process. All scripts now include comprehensive error handling and reporting.

## Additional Options

The `reencrypt.sh` script supports the following options:

```
Usage: ./reencrypt.sh [options]
Options:
  -n, --namespace <namespace>  Specify a namespace (default: all namespaces)
  -a, --all-namespaces         Search in all namespaces (default: true)
  -l, --log-level <level>      Set log level: debug, info, warn, error (default: info)
  -f, --log-file <file>        Log file (default: reencryption.log)
  -d, --dry-run                Show what would be done without making changes
  -h, --help                   Display this help message
```

