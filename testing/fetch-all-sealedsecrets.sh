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
cat $SEALED_SECRETS