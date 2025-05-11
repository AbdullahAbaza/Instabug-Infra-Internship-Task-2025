#!/bin/bash

# Script to re-encrypt SealedSecrets in a Kubernetes cluster
# This is a test implementation of the plan outlined in Automating_re-encryption_of_SealedSecrets.md

set -e

# Global variables
NAMESPACE=""
ALL_NAMESPACES=true
PUBLIC_KEY_FILE="latest-public-key.pem"
LOG_FILE="reencryption.log"
DRY_RUN=false
LOG_LEVEL="info"
TEMP_DIR=""

# Function to display usage information
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -n, --namespace <namespace>  Specify a namespace (default: all namespaces)"
    echo "  -a, --all-namespaces         Search in all namespaces (default: true)"
    echo "  -l, --log-level <level>      Set log level: debug, info, warn, error (default: info)"
    echo "  -f, --log-file <file>        Log file (default: reencryption.log)"
    echo "  -d, --dry-run                Show what would be done without making changes"
    echo "  -h, --help                   Display this help message"
    exit 1
}

# Function to log messages with timestamp and severity
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Only log if the current level is appropriate
    case "$LOG_LEVEL" in
        debug)
            # Log everything
            ;;
        info)
            # Don't log debug
            if [ "$level" = "DEBUG" ]; then
                return
            fi
            ;;
        warn)
            # Don't log debug or info
            if [ "$level" = "DEBUG" ] || [ "$level" = "INFO" ]; then
                return
            fi
            ;;
        error)
            # Only log errors
            if [ "$level" != "ERROR" ]; then
                return
            fi
            ;;
    esac

    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Function to list all SealedSecrets in the cluster
list_sealed_secrets() {
    local namespace="$1"
    local all_namespaces="$2"

    log "INFO" "Listing SealedSecrets..."

    local result=""
    if [ "$all_namespaces" = true ]; then
        log "DEBUG" "Searching in all namespaces"
        result=$(kubectl get sealedsecrets --all-namespaces -o json | jq -r '.items[] | .metadata.namespace + "/" + .metadata.name')
    else
        log "DEBUG" "Searching in namespace: $namespace"
        result=$(kubectl get sealedsecrets -n "$namespace" -o json | jq -r '.items[] | .metadata.namespace + "/" + .metadata.name')
    fi

    echo "$result"
}

# Function to fetch the latest public key from the sealed-secrets controller
fetch_latest_public_key() {
    local output_file="$1"

    log "INFO" "Fetching latest public key from sealed-secrets controller..."

    # Get the controller service name
    log "DEBUG" "Getting sealed-secrets controller service name..."
    CONTROLLER_NAME=$(kubectl get service -n kube-system -l app.kubernetes.io/name=sealed-secrets -o jsonpath="{.items[0].metadata.name}")
    log "DEBUG" "Controller service name: $CONTROLLER_NAME"

    # Fetch the public key using kubeseal
    if ! kubeseal --controller-name=$CONTROLLER_NAME --controller-namespace=kube-system --fetch-cert > "$output_file"; then
        log "ERROR" "Failed to fetch public key from sealed-secrets controller"
        return 1
    fi

    log "INFO" "Successfully fetched public key to $output_file"
    return 0
}

# Function to re-encrypt a SealedSecret with the latest key
reencrypt_sealed_secret() {
    local namespace="$1"
    local name="$2"
    local public_key_file="$3"
    local temp_dir="$4"

    log "INFO" "Re-encrypting SealedSecret $namespace/$name..."

    # Create temporary files
    local sealed_secret_file="$temp_dir/$namespace-$name-sealed.yaml"
    local raw_secret_file="$temp_dir/$namespace-$name-raw.yaml"
    local new_sealed_secret_file="$temp_dir/$namespace-$name-new-sealed.yaml"

    # Get the SealedSecret
    log "DEBUG" "Getting SealedSecret $namespace/$name"
    if ! kubectl get sealedsecret "$name" -n "$namespace" -o yaml > "$sealed_secret_file"; then
        log "ERROR" "Failed to get SealedSecret $namespace/$name"
        return 1
    fi

    # Extract the raw Secret using the controller
    # Note: In a real implementation, this would require controller involvement
    # or access to the private key. This is a simplified example.
    log "DEBUG" "Extracting raw Secret from SealedSecret $namespace/$name"

    # For demonstration purposes, we'll assume we have a way to get the raw Secret
    # In reality, this would be more complex and would involve the controller
    if ! kubectl get secret "$name" -n "$namespace" -o yaml > "$raw_secret_file" 2>/dev/null; then
        log "ERROR" "Failed to get raw Secret for $namespace/$name"
        return 1
    fi

    # Re-encrypt the raw Secret with the latest key
    log "DEBUG" "Re-encrypting Secret $namespace/$name with latest key"
    if ! kubeseal --controller-name=$CONTROLLER_NAME --controller-namespace=kube-system --cert "$public_key_file" --format yaml < "$raw_secret_file" > "$new_sealed_secret_file"; then
        log "ERROR" "Failed to re-encrypt Secret $namespace/$name"
        return 1
    fi

    # Update the SealedSecret in the cluster (unless dry run)
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "DRY RUN: Would update SealedSecret $namespace/$name"
    else
        log "DEBUG" "Updating SealedSecret $namespace/$name in the cluster"
        if ! kubectl apply -f "$new_sealed_secret_file"; then
            log "ERROR" "Failed to update SealedSecret $namespace/$name"
            return 1
        fi
    fi

    log "INFO" "Successfully re-encrypted SealedSecret $namespace/$name"
    return 0
}

# Main function to re-encrypt all SealedSecrets
reencrypt_all_sealed_secrets() {
    local namespace="$1"
    local all_namespaces="$2"
    local public_key_file="$3"

    # List all SealedSecrets
    log "INFO" "Retrieving list of SealedSecrets..."
    local sealed_secrets
    sealed_secrets=$(list_sealed_secrets "$namespace" "$all_namespaces")

    if [ -z "$sealed_secrets" ]; then
        log "WARN" "No SealedSecrets found"
        return 0
    fi

    # Filter out any log messages (lines starting with '[')
    sealed_secrets=$(echo "$sealed_secrets" | grep -v '^\[')

    # Count the number of SealedSecrets
    local count=$(echo "$sealed_secrets" | wc -l)
    log "INFO" "Found $count SealedSecrets to re-encrypt"

    # Re-encrypt each SealedSecret
    local success_count=0
    local total_count=0

    while IFS= read -r ss; do
        if [ -z "$ss" ]; then
            continue
        fi

        # Validate the format (should be namespace/name)
        if [[ ! "$ss" =~ ^[^/]+/[^/]+$ ]]; then
            log "WARN" "Invalid SealedSecret format: $ss, skipping"
            continue
        fi

        total_count=$((total_count + 1))

        # Split namespace and name
        local ss_namespace=$(echo "$ss" | cut -d '/' -f 1)
        local ss_name=$(echo "$ss" | cut -d '/' -f 2)

        if reencrypt_sealed_secret "$ss_namespace" "$ss_name" "$public_key_file" "$TEMP_DIR"; then
            success_count=$((success_count + 1))
        fi
    done <<< "$sealed_secrets"

    log "INFO" "Re-encryption complete. Successfully re-encrypted $success_count/$total_count SealedSecrets"

    return 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--namespace)
            NAMESPACE="$2"
            ALL_NAMESPACES=false
            shift 2
            ;;
        -a|--all-namespaces)
            ALL_NAMESPACES=true
            shift
            ;;
        -l|--log-level)
            LOG_LEVEL="$2"
            shift 2
            ;;
        -f|--log-file)
            LOG_FILE="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate log level
case "$LOG_LEVEL" in
    debug|info|warn|error)
        # Valid log level
        ;;
    *)
        echo "Invalid log level: $LOG_LEVEL"
        usage
        ;;
esac

# Create log file
> "$LOG_FILE"
log "INFO" "Starting SealedSecret re-encryption process"
log "INFO" "Log level: $LOG_LEVEL"

# Create temporary directory
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
log "DEBUG" "Created temporary directory: $TEMP_DIR"

# Fetch the latest public key
fetch_latest_public_key "$PUBLIC_KEY_FILE"

# Re-encrypt all SealedSecrets
reencrypt_all_sealed_secrets "$NAMESPACE" "$ALL_NAMESPACES" "$PUBLIC_KEY_FILE"

log "INFO" "Re-encryption process completed"
