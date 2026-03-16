#!/bin/bash

# ==============================================================================
# Kueue, LWS, and JobSet Setup Script
#
# This script handles the download, patching, and application (or deletion)
# of Kubernetes manifests for Kueue and optionally LeaderWorkerSet (LWS)
# and JobSet. It uses a dedicated script to apply custom patches to Kueue.
#
# Usage: ./setup_cluster.sh {create|delete|ignore} [options]
#
# Actions:
#   create: Downloads, patches, and applies Kueue (and LWS/JobSet if enabled).
#   delete: Deletes Kueue (and LWS/JobSet if enabled) manifests.
#   ignore: Skips all manifest operations.
#
# Options:
#   --kueue-version <tag|minor|latest|main> Default: v0.11.4. Can be a full tag (v0.11.4),
#                                           a minor version (v0.11), 'latest', or 'main'.
#   --reduced-mode <true|false>     Default: false. If true, LWS is skipped and
#                                   Kueue is patched with reduced features.
#   --enable-tas <true|false>       Default: true. If false, Kueue TAS is disabled.
#   --install-jobset <true|false>   Default: false. If true, JobSet is installed.
#   --high-throughput <true|false>  Default: true. Bumps Kueue controller concurrency.
#   --replicas <count>              Override Kueue manager replica count (manifest default: 1).
#   --cpu <value>                   Override Kueue manager CPU for request & limit.
#   --memory <value>                Override Kueue manager memory for request & limit.
# ==============================================================================

# Exit immediately if a command exits with a non-zero status.
#set -e

# --- Configuration ---
# Determine the directory where the script resides.
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Define paths to supporting scripts and patches for LWS/JobSet.
KUEUE_PATCHER_SCRIPT="${SCRIPT_DIR}/kueue_patcher_script.sh"
MANIFEST_LWS_DIFF="${SCRIPT_DIR}/lws.diff"
MANIFEST_JOBSET_DIFF="${SCRIPT_DIR}/jobset.diff"

# Define versions and URLs for other components.
LWS_VERSION="v0.5.1"
LWS_URL="https://github.com/kubernetes-sigs/lws/releases/download/${LWS_VERSION}/manifests.yaml"
JOBSET_VERSION="v0.8.1"
JOBSET_URL="https://github.com/kubernetes-sigs/jobset/releases/download/${JOBSET_VERSION}/manifests.yaml"

# Define local manifest filenames.
KUEUE_MANIFEST="kueue.yaml"
LWS_MANIFEST="lws.yaml"
JOBSET_MANIFEST="jobset.yaml"

# --- Helper Functions ---

# A function to log errors and exit
fail() {
  echo "[ERROR] $1" >&2
  exit 1
}

# Checks if a command is available in the system.
check_command() {
  if ! command -v "$1" &> /dev/null; then
    fail "Required command '$1' not found. Please install it."
  fi
}

# Prints usage information and exits.
print_usage_and_exit() {
  echo "Error: Invalid arguments." >&2
  echo "Usage: $0 {create|delete|ignore} [options]" >&2
  echo "Actions:" >&2
  echo "  create|delete|ignore                (Mandatory)" >&2
  echo "Options:" >&2
  echo "  --kueue-version <tag|minor|latest|main> (Default: v0.11.4). Minor (e.g., 'v0.11') resolves to the latest patch." >&2
  echo "  --reduced-mode <true|false>         (Default: false)" >&2
  echo "  --enable-tas <true|false>          (Default: true)" >&2
  echo "  --install-jobset <true|false>       (Default: false)" >&2
  echo "  --high-throughput <true|false>      (Default: true)" >&2
  echo "  --replicas <count>                  Override Kueue manager replica count (manifest default: 1)." >&2
  echo "  --cpu <value>                       Override Kueue manager CPU for request & limit." >&2
  echo "  --memory <value>                    Override Kueue manager memory for request & limit." >&2
  exit 1
}

# Downloads a manifest file from a URL.
# $1: Component Name (e.g., "LWS")
# $2: Version
# $3: URL
# $4: Output filename
download_manifest() {
    echo "Downloading $1 manifests (${2}) from ${3}..."
    wget --progress=bar:force:noscroll -O "$4" "$3"
}

# Applies a patch to a manifest file if the patch exists.
# $1: Manifest filename
# $2: Patch filename
# $3: Patch description
apply_patch_if_exists() {
    if [ -f "$2" ]; then
        echo "Applying $3 patch to $1 ($2)..."
        patch "$1" "$2"
    fi
}

# --- Main Logic Functions ---

# Parses and validates all script arguments.
parse_args() {
    if [ "$#" -lt 1 ]; then
        print_usage_and_exit
    fi

    ACTION="$1"
    shift # Consume the action

    # Set defaults for optional flags
    KUEUE_VERSION="v0.11.4"
    REDUCED_MODE=false
    KUEUE_TAS_ENABLED=true
    INSTALL_JOBSET=false
    HIGH_THROUGHPUT=true
    REPLICAS=""
    CPU=""
    MEMORY=""

    # Parse optional flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --kueue-version) KUEUE_VERSION="$2"; shift 2;;
            --reduced-mode) REDUCED_MODE="$2"; shift 2;;
            --enable-tas) KUEUE_TAS_ENABLED="$2"; shift 2;;
            --install-jobset) INSTALL_JOBSET="$2"; shift 2;;
            --high-throughput) HIGH_THROUGHPUT="$2"; shift 2;;
            --replicas) REPLICAS="$2"; shift 2;;
            --cpu) CPU="$2"; shift 2;;
            --memory) MEMORY="$2"; shift 2;;
            *) echo "Error: Unknown option '$1'." >&2; print_usage_and_exit;;
        esac
    done

    # Validate mandatory action
    case "$ACTION" in
        create|delete|ignore)
            ;;
        *)
            echo "Error: Invalid action '$ACTION'." >&2
            print_usage_and_exit
            ;;
    esac

    # Echo settings
    echo "--- Mode: ${ACTION} ---"
    echo "Kueue Version: ${KUEUE_VERSION}"
    echo "Reduced Mode: ${REDUCED_MODE}"
    echo "Kueue TAS Enabled: ${KUEUE_TAS_ENABLED}"
    echo "Install JobSet: ${INSTALL_JOBSET}"
    echo "High Throughput: ${HIGH_THROUGHPUT}"
    [ -n "$REPLICAS" ] && echo "Custom Replicas: ${REPLICAS}"
    [ -n "$CPU" ] && echo "Custom CPU: ${CPU}"
    [ -n "$MEMORY" ] && echo "Custom Memory: ${MEMORY}"
}

# Handles the download and patching of all manifests.
handle_downloads_and_patches() {
    local needs_download=false
    if [[ "$ACTION" == "create" ]]; then
        needs_download=true
    elif [[ "$ACTION" == "delete" ]]; then
        # Check if manifests are missing for the delete operation.
        if [[ ! -f "$KUEUE_MANIFEST" ]] || \
           [[ "$REDUCED_MODE" == "false" && ! -f "$LWS_MANIFEST" ]] || \
           [[ "$INSTALL_JOBSET" == "true" && ! -f "$JOBSET_MANIFEST" ]]; then
            needs_download=true
        fi
    fi

    if [[ "$needs_download" == "false" ]]; then
        return
    fi

    echo "--- Downloading and Patching Manifests ---"

    # --- Kueue Manifest ---
    case "$KUEUE_VERSION" in
        main)
            echo "Downloading Kueue from main branch using kustomize..."
            check_command kubectl # kubectl kustomize is required
            kubectl kustomize "github.com/kubernetes-sigs/kueue/config/default?ref=main" > "$KUEUE_MANIFEST"
            ;;
        latest)
            local url="https://github.com/kubernetes-sigs/kueue/releases/latest/download/manifests.yaml"
            download_manifest "Kueue" "latest release" "$url" "$KUEUE_MANIFEST"
            ;;
        v*.*) # This case handles both minor (v0.11) and full (v0.11.4) versions
            if [[ "$KUEUE_VERSION" =~ ^v[0-9]+\.[0-9]+$ ]]; then
                local minor_version=$KUEUE_VERSION
                echo "Searching for the latest patch release for minor version ${minor_version}..."
                check_command curl
                check_command jq
                local resolved_version
                resolved_version=$(curl -s "https://api.github.com/repos/kubernetes-sigs/kueue/releases" | jq -r '.[].tag_name' | grep "^${minor_version}\." | sort -V | tail -n 1)

                if [ -z "$resolved_version" ]; then
                    fail "Could not find any patch release for minor version ${minor_version}."
                fi

                echo "Resolved ${minor_version} to latest patch release: ${resolved_version}"
                KUEUE_VERSION="$resolved_version" # Update the variable for later use
            fi

            # This logic now works for both fully specified and resolved minor versions
            local url="https://github.com/kubernetes-sigs/kueue/releases/download/${KUEUE_VERSION}/manifests.yaml"
            download_manifest "Kueue" "$KUEUE_VERSION" "$url" "$KUEUE_MANIFEST"
            ;;
        *)
            fail "Invalid Kueue version format: '${KUEUE_VERSION}'. Expected a tag like 'vX.Y.Z', a minor version 'vX.Y', 'latest', or 'main'."
            ;;
    esac

    # This part remains the same: apply custom patches after downloading.
    echo "Applying custom patches to Kueue manifest using ${KUEUE_PATCHER_SCRIPT}..."
    if [ ! -f "$KUEUE_PATCHER_SCRIPT" ]; then
        fail "Patcher script not found at ${KUEUE_PATCHER_SCRIPT}"
    fi
    local patcher_opts=()
    patcher_opts+=(--enable-tas "$KUEUE_TAS_ENABLED")
    patcher_opts+=(--high-throughput "$HIGH_THROUGHPUT")
    if [[ "$REDUCED_MODE" == "true" ]]; then
        patcher_opts+=(--integrations false)
        patcher_opts+=(--fair-sharing false)
    else
        patcher_opts+=(--integrations true)
        patcher_opts+=(--fair-sharing true)
    fi
    if [ -n "$REPLICAS" ]; then patcher_opts+=(--replicas "$REPLICAS"); fi
    if [ -n "$CPU" ]; then patcher_opts+=(--cpu "$CPU"); fi
    if [ -n "$MEMORY" ]; then patcher_opts+=(--memory "$MEMORY"); fi
    local patched_kueue_manifest="${KUEUE_MANIFEST}.patched"
    bash "$KUEUE_PATCHER_SCRIPT" "${patcher_opts[@]}" "$KUEUE_MANIFEST" "$patched_kueue_manifest"
    mv "$patched_kueue_manifest" "$KUEUE_MANIFEST"
    echo "Kueue manifest has been patched."

    # --- LWS Manifest ---
    if [[ "$REDUCED_MODE" == "false" ]]; then
        download_manifest "LWS" "$LWS_VERSION" "$LWS_URL" "$LWS_MANIFEST"
        apply_patch_if_exists "$LWS_MANIFEST" "$MANIFEST_LWS_DIFF" "LWS"
    else
        echo "Skipping LWS download and patch (reduced mode)."
    fi

    # --- JobSet Manifest ---
    if [[ "$INSTALL_JOBSET" == "true" ]]; then
        download_manifest "JobSet" "$JOBSET_VERSION" "$JOBSET_URL" "$JOBSET_MANIFEST"
        apply_patch_if_exists "$JOBSET_MANIFEST" "$MANIFEST_JOBSET_DIFF" "JobSet"
    else
        echo "Skipping JobSet download and patch."
    fi

    echo "--- Manifests Ready ---"
}

# Applies all enabled manifests to the cluster.
apply_manifests() {
    echo "--- Applying Manifests ---"

    if [[ "$INSTALL_JOBSET" == "true" ]]; then
        echo "Applying JobSet manifests ($JOBSET_MANIFEST)..."
        kubectl apply --server-side -f "$JOBSET_MANIFEST"
        echo "Waiting for JobSet controller manager deployment..."
        kubectl wait deploy/jobset-controller-manager -njobset-system --for=condition=available --timeout=10m
    fi

    echo "Applying Kueue core manifests ($KUEUE_MANIFEST)..."
    kubectl apply --server-side -f "$KUEUE_MANIFEST"
    echo "Waiting for Kueue controller manager deployment..."
    kubectl wait deploy/kueue-controller-manager -nkueue-system --for=condition=available --timeout=20m

    local kueue_prometheus_url="https://github.com/kubernetes-sigs/kueue/releases/latest/download/prometheus.yaml"
    if [[ "$KUEUE_VERSION" != "main" && "$KUEUE_VERSION" != "latest" ]]; then
      kueue_prometheus_url="https://github.com/kubernetes-sigs/kueue/releases/download/${KUEUE_VERSION}/prometheus.yaml"
    fi
    echo "Applying Kueue Prometheus manifests from ${kueue_prometheus_url}..."
    kubectl apply --server-side -f "$kueue_prometheus_url"

    if [[ "$REDUCED_MODE" == "false" ]]; then
        echo "Applying LWS manifests ($LWS_MANIFEST)..."
        kubectl apply --server-side -f "$LWS_MANIFEST"
        echo "Waiting for LWS webhook deployment..."
        kubectl wait deploy/lws-controller-manager -nlws-system --for=condition=available --timeout=10m
    fi

    echo "--- Manifests Applied Successfully ---"
}

# Deletes all enabled manifests from the cluster.
delete_manifests() {
    echo "--- Deleting Manifests ---"

    # Delete dependent manifests first.
    if [[ "$REDUCED_MODE" == "false" ]]; then
        echo "Deleting LWS manifests ($LWS_MANIFEST)..."
        kubectl delete --ignore-not-found=true -f "${LWS_MANIFEST:-$LWS_URL}" || echo "Warning: Failed to delete LWS."
    fi

    if [[ "$INSTALL_JOBSET" == "true" ]]; then
        echo "Deleting JobSet manifests ($JOBSET_MANIFEST)..."
        kubectl delete --ignore-not-found=true -f "${JOBSET_MANIFEST:-$JOBSET_URL}" || echo "Warning: Failed to delete JobSet."
    fi

    # Delete Kueue last.
    local kueue_prometheus_url="https://github.com/kubernetes-sigs/kueue/releases/latest/download/prometheus.yaml"
    if [[ "$KUEUE_VERSION" != "main" && "$KUEUE_VERSION" != "latest" ]]; then
      kueue_prometheus_url="https://github.com/kubernetes-sigs/kueue/releases/download/${KUEUE_VERSION}/prometheus.yaml"
    fi
    echo "Deleting Kueue Prometheus manifests from ${kueue_prometheus_url}..."
    kubectl delete --ignore-not-found=true -f "$kueue_prometheus_url"

    echo "Deleting Kueue core manifests ($KUEUE_MANIFEST)..."
    kubectl delete --ignore-not-found=true -f "$KUEUE_MANIFEST" || echo "Warning: Failed to delete Kueue."

    echo "--- Manifests Deletion Attempted ---"
}

# --- Script Entrypoint ---
main() {
    # --- Pre-checks ---
    check_command wget
    check_command patch # Still needed for LWS and JobSet
    check_command kubectl
    check_command curl
    check_command jq


    parse_args "$@"

    if [[ "$ACTION" == "ignore" ]]; then
        echo "Action is 'ignore'. Skipping all manifest operations."
        exit 0
    fi

    handle_downloads_and_patches

    case "$ACTION" in
        create)
            apply_manifests
            ;;
        delete)
            delete_manifests
            ;;
    esac

    echo "Script finished."
}

# Pass all script arguments to the main function.
main "$@"
exit 0
