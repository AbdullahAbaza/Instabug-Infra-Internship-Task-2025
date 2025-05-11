# Automating Re-encryption of SealedSecrets

## Introduction

This document outlines a plan for implementing an automated re-encryption mechanism for SealedSecrets in a Kubernetes cluster. The proposed feature will extend the functionality of the kubeseal CLI tool to allow users to easily re-encrypt all SealedSecrets after a key rotation has occurred.

## Background

Bitnami's sealed-secrets controller performs key rotation every 30 days by default. While this enhances security, it creates a challenge: existing SealedSecrets are not automatically re-encrypted with the new key. This means that if the old keys are lost or removed, those SealedSecrets can no longer be decrypted.

Our solution addresses this gap by providing an automated way to re-encrypt all existing SealedSecrets with the latest key, ensuring they remain accessible even after multiple key rotations.

## Implementation Plan

### 1. Extending the kubeseal CLI

The re-encryption mechanism will be implemented as a new subcommand for the kubeseal CLI tool: `kubeseal reencrypt`. This command will:

1. Identify all SealedSecrets in the cluster
2. Fetch the latest public key from the controller
3. For each SealedSecret:
   - Decrypt it using the controller's existing private keys
   - Re-encrypt it using the latest public key
   - Update the SealedSecret object in the cluster

#### Design Considerations

- The implementation should build upon the existing kubeseal codebase
- The command should support various flags for flexibility (namespace selection, verbosity, etc.)
- The process should be secure, ensuring private keys never leave the cluster

### 2. Identifying SealedSecrets in the Cluster

The first step is to identify all SealedSecrets in the cluster. We'll use the Kubernetes API to list all SealedSecret objects.

#### Implementation Description

We would extend the kubeseal CLI to include functionality that:

1. Connects to the Kubernetes API server
2. Lists all SealedSecret objects across all namespaces or in a specific namespace
3. Returns the list for processing

#### Bash Example

```bash
#!/bin/bash

# Function to list all SealedSecrets in the cluster
list_sealed_secrets() {
    local namespace="$1"
    local all_namespaces="$2"

    if [ "$all_namespaces" = true ]; then
        kubectl get sealedsecrets --all-namespaces -o json | jq -r '.items[] | .metadata.namespace + "/" + .metadata.name'
    else
        kubectl get sealedsecrets -n "$namespace" -o json | jq -r '.items[] | .metadata.namespace + "/" + .metadata.name'
    fi
}

# Example usage
NAMESPACE="default"
ALL_NAMESPACES=true
SEALED_SECRETS=$(list_sealed_secrets "$NAMESPACE" "$ALL_NAMESPACES")
```

### 3. Fetching the Latest Public Key

Next, we need to fetch the latest public key from the sealed-secrets controller.

#### Implementation Description

The kubeseal CLI already has functionality to fetch the public key. We would leverage this existing code to:

1. Connect to the sealed-secrets controller
2. Retrieve the latest public key certificate
3. Use this certificate for re-encryption

#### Bash Example

```bash
#!/bin/bash

# Function to fetch the latest public key from the sealed-secrets controller
fetch_latest_public_key() {
    local output_file="$1"

    # Fetch the public key using kubeseal
    if ! kubeseal --fetch-cert > "$output_file"; then
        echo "Error: Failed to fetch public key from sealed-secrets controller" >&2
        return 1
    fi

    echo "Successfully fetched public key to $output_file"
    return 0
}

# Example usage
PUBLIC_KEY_FILE="latest-public-key.pem"
fetch_latest_public_key "$PUBLIC_KEY_FILE"
```

### 4. Re-encrypting SealedSecrets

Now we'll implement the core functionality to re-encrypt each SealedSecret with the latest key.

#### Implementation Description

This is the most complex part of the implementation. We would need to:

1. For each SealedSecret:
   - Retrieve the SealedSecret object
   - Use the controller to decrypt it (this ensures private keys never leave the cluster)
   - Re-encrypt the raw Secret with the latest public key
   - Update the SealedSecret in the cluster with the new encrypted data

#### Bash Example

```bash
#!/bin/bash

# Function to re-encrypt a SealedSecret with the latest key
reencrypt_sealed_secret() {
    local namespace="$1"
    local name="$2"
    local public_key_file="$3"
    local temp_dir="$4"

    echo "Re-encrypting SealedSecret $namespace/$name..."

    # Create temporary files
    local sealed_secret_file="$temp_dir/$namespace-$name-sealed.yaml"
    local raw_secret_file="$temp_dir/$namespace-$name-raw.yaml"
    local new_sealed_secret_file="$temp_dir/$namespace-$name-new-sealed.yaml"

    # Get the SealedSecret
    if ! kubectl get sealedsecret "$name" -n "$namespace" -o yaml > "$sealed_secret_file"; then
        echo "Error: Failed to get SealedSecret $namespace/$name" >&2
        return 1
    fi

    # Extract the raw Secret using the controller
    # Note: In a real implementation, this would require controller involvement
    # or access to the private key. This is a simplified example.
    echo "Extracting raw Secret from SealedSecret $namespace/$name..."

    # For demonstration purposes, we'll assume we have a way to get the raw Secret
    # In reality, this would be more complex and would involve the controller
    if ! kubectl get secret "$name" -n "$namespace" -o yaml > "$raw_secret_file" 2>/dev/null; then
        echo "Error: Failed to get raw Secret for $namespace/$name" >&2
        return 1
    fi

    # Re-encrypt the raw Secret with the latest key
    echo "Re-encrypting Secret $namespace/$name with latest key..."
    if ! kubeseal --cert "$public_key_file" --format yaml < "$raw_secret_file" > "$new_sealed_secret_file"; then
        echo "Error: Failed to re-encrypt Secret $namespace/$name" >&2
        return 1
    fi

    # Update the SealedSecret in the cluster
    echo "Updating SealedSecret $namespace/$name in the cluster..."
    if ! kubectl apply -f "$new_sealed_secret_file"; then
        echo "Error: Failed to update SealedSecret $namespace/$name" >&2
        return 1
    fi

    echo "Successfully re-encrypted SealedSecret $namespace/$name"
    return 0
}
```

### 5. Main Re-encryption Process

The main process will tie all the components together.

#### Bash Example

```bash
#!/bin/bash

# Main function to re-encrypt all SealedSecrets
reencrypt_all_sealed_secrets() {
    local namespace="$1"
    local all_namespaces="$2"
    local public_key_file="$3"

    # Create temporary directory
    local temp_dir=$(mktemp -d)
    trap 'rm -rf "$temp_dir"' EXIT

    # List all SealedSecrets
    local sealed_secrets
    sealed_secrets=$(list_sealed_secrets "$namespace" "$all_namespaces")

    if [ -z "$sealed_secrets" ]; then
        echo "No SealedSecrets found"
        return 0
    fi

    echo "Found the following SealedSecrets to re-encrypt:"
    echo "$sealed_secrets"

    # Re-encrypt each SealedSecret
    local success_count=0
    local total_count=0

    while IFS= read -r ss; do
        if [ -z "$ss" ]; then
            continue
        fi

        total_count=$((total_count + 1))

        # Split namespace and name
        local ss_namespace=$(echo "$ss" | cut -d '/' -f 1)
        local ss_name=$(echo "$ss" | cut -d '/' -f 2)

        if reencrypt_sealed_secret "$ss_namespace" "$ss_name" "$public_key_file" "$temp_dir"; then
            success_count=$((success_count + 1))
        fi
    done <<< "$sealed_secrets"

    echo "Re-encryption complete. Successfully re-encrypted $success_count/$total_count SealedSecrets"

    return 0
}

# Example usage
NAMESPACE=""
ALL_NAMESPACES=true
PUBLIC_KEY_FILE="latest-public-key.pem"

# Fetch the latest public key
fetch_latest_public_key "$PUBLIC_KEY_FILE"

# Re-encrypt all SealedSecrets
reencrypt_all_sealed_secrets "$NAMESPACE" "$ALL_NAMESPACES" "$PUBLIC_KEY_FILE"
```

## Bonus Features

### 1. Logging and Reporting

To enhance the re-encryption process with comprehensive logging and reporting, we would implement:

1. **Structured Logging**: Detailed logs with timestamps, severity levels, and contextual information
2. **Progress Reporting**: Real-time updates on the re-encryption progress
3. **Summary Report**: A comprehensive report at the end of the process
4. **Error Aggregation**: Collection and categorization of errors for easier troubleshooting

#### Bash Example for Enhanced Logging

```bash
#!/bin/bash

# Function to log messages with timestamp and severity
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "[$timestamp] [$level] $message"
}

# Enhanced re-encryption function with better logging
reencrypt_sealed_secret_with_logging() {
    local namespace="$1"
    local name="$2"
    local public_key_file="$3"
    local temp_dir="$4"
    local log_file="$5"

    log "INFO" "Starting re-encryption of SealedSecret $namespace/$name" | tee -a "$log_file"

    # ... [rest of the re-encryption logic] ...

    if [ $success -eq 1 ]; then
        log "SUCCESS" "Successfully re-encrypted SealedSecret $namespace/$name" | tee -a "$log_file"
    else
        log "ERROR" "Failed to re-encrypt SealedSecret $namespace/$name: $error_message" | tee -a "$log_file"
    fi

    return $success
}

### 2. Handling Large Numbers of SealedSecrets

For clusters with a large number of SealedSecrets, we need to ensure our implementation is efficient and doesn't overwhelm the Kubernetes API server. We would implement:

1. **Batch Processing**: Process SealedSecrets in batches to limit API server load
2. **Parallel Processing**: Use concurrent processing to speed up the re-encryption
3. **Rate Limiting**: Implement rate limiting to avoid overwhelming the API server
4. **Resumable Operations**: Allow the process to be resumed if interrupted

#### Bash Example for Batch Processing

```bash
#!/bin/bash

# Function to re-encrypt SealedSecrets in batches
reencrypt_sealed_secrets_in_batches() {
    local sealed_secrets=("$@")
    local batch_size=10
    local total=${#sealed_secrets[@]}
    local batches=$(( (total + batch_size - 1) / batch_size ))

    log "INFO" "Processing $total SealedSecrets in $batches batches of up to $batch_size each"

    for ((i=0; i<total; i+=batch_size)); do
        local end=$((i + batch_size))
        if [ $end -gt $total ]; then
            end=$total
        fi

        log "INFO" "Processing batch $((i/batch_size + 1))/$batches (SealedSecrets $((i+1))-$end of $total)"

        # Process this batch
        for ((j=i; j<end; j++)); do
            local ss=${sealed_secrets[$j]}
            local ss_namespace=$(echo "$ss" | cut -d '/' -f 1)
            local ss_name=$(echo "$ss" | cut -d '/' -f 2)

            reencrypt_sealed_secret "$ss_namespace" "$ss_name" "$PUBLIC_KEY_FILE" "$TEMP_DIR"
        done

        # Add a small delay between batches to avoid overwhelming the API server
        sleep 2
    done
}
```

### 3. Security of Private Keys

Ensuring the security of private keys is critical. Our implementation would:

1. **Never Extract Private Keys**: The private keys should never leave the Kubernetes cluster
2. **Use Controller APIs**: Leverage the controller's APIs for decryption operations
3. **Implement Proper Authentication**: Ensure only authorized users can perform re-encryption
4. **Audit Logging**: Log all access to sensitive operations

#### Implementation Description

For the actual implementation, we would extend the kubeseal CLI to communicate with the sealed-secrets controller for decryption operations, rather than attempting to extract or use the private keys directly. This ensures the private keys remain secure within the cluster.

## Usage Guide

Once implemented, the re-encryption feature can be used as follows:

```bash
# Re-encrypt all SealedSecrets in all namespaces
kubeseal reencrypt --all-namespaces

# Re-encrypt SealedSecrets in a specific namespace
kubeseal reencrypt --namespace my-namespace

# Dry run to see what would be re-encrypted without making changes
kubeseal reencrypt --all-namespaces --dry-run

# Increase log verbosity
kubeseal reencrypt --all-namespaces --log-level debug

# Output detailed logs to a file
kubeseal reencrypt --all-namespaces --log-file reencryption.log
```

## Integration with CI/CD Pipelines

The re-encryption feature can be integrated into CI/CD pipelines to automatically re-encrypt SealedSecrets after key rotation:

```yaml
# Example GitHub Actions workflow
name: Re-encrypt SealedSecrets

on:
  # Run on a schedule (e.g., monthly)
  schedule:
    - cron: '0 0 1 * *'  # Run at midnight on the 1st of every month

  # Allow manual triggering
  workflow_dispatch:

jobs:
  reencrypt:
    runs-on: ubuntu-latest
    steps:
      - name: Set up kubeconfig
        run: |
          echo "${{ secrets.KUBECONFIG }}" > kubeconfig.yaml
          export KUBECONFIG=kubeconfig.yaml

      - name: Install kubeseal
        run: |
          KUBESEAL_VERSION=$(curl -s https://api.github.com/repos/bitnami-labs/sealed-secrets/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
          wget "https://github.com/bitnami-labs/sealed-secrets/releases/download/${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION#v}-linux-amd64.tar.gz"
          tar -xvzf "kubeseal-${KUBESEAL_VERSION#v}-linux-amd64.tar.gz"
          sudo install -m 755 kubeseal /usr/local/bin/kubeseal

      - name: Re-encrypt SealedSecrets
        run: |
          kubeseal reencrypt --all-namespaces --log-file reencryption.log

      - name: Upload logs
        uses: actions/upload-artifact@v2
        with:
          name: reencryption-logs
          path: reencryption.log
```

## Conclusion

The automated re-encryption mechanism for SealedSecrets provides a valuable enhancement to the kubeseal CLI, addressing a key operational challenge in managing encrypted secrets in Kubernetes. By implementing this feature, users can ensure that their SealedSecrets remain accessible even after key rotation, without manual intervention.

The implementation leverages the existing kubeseal codebase and follows best practices for Kubernetes controller interactions, security, and performance. The feature is designed to be user-friendly, with clear documentation and integration capabilities for CI/CD pipelines.

By following the implementation plan outlined in this document, developers can extend the kubeseal CLI to provide this important functionality, enhancing the overall security and manageability of Kubernetes secrets.
