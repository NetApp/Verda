#!/usr/bin/env bash

################################################################################
# NetApp Console API - Create and Protect a Kubernetes Application
#
# Creates an application in Backup and Recovery for Kubernetes and assigns a
# protection policy to it. Variables follow 00-authentication/env.sh.example.
# Requires: curl, jq
################################################################################

# shellcheck source=../lib/bnr-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/bnr-common.sh"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Usage
################################################################################
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Required:
  --org-id        ID            Console organization id
  --agent-id      ID            Console agent id
  --cluster-name  NAME          Kubernetes cluster name
  --app-name      NAME          Application name to create
  --namespaces    NS1[,NS2,..]  Comma-separated list of namespaces
  --policy-name   NAME          Protection policy name

Optional:
  --account-id    ID            Account id (default: organization id)
  --api-host      URL           API host (default: CONSOLE_API, else
                                https://cloudmanager.cloud.netapp.com)
  --response-file FILE          Where to save the create response
                                (default: /tmp/netapp_create_app_response.json)
  --label-selectors SEL1[,SEL2,..]  Comma-separated label selectors, for example color=green
  --app-type      TYPE          virtual-machine-label-selector
                                Selects virtual machines by namespace and label.
                                Requires --label-selectors.
  --skip-vm-freeze              Do not freeze virtual machines (VM app type)
  --simultaneous-vm-freeze      Freeze every selected virtual machine together
  --vm-freeze-max N             Max virtual machines frozen at once
  --site-prefix   PREFIX        Prefix added to each name in --policy-file
  --policy-file   FILE          File with one policy name per line
                                Both flags are required together. Each name is
                                prefixed, then looked up. The script stops if
                                any prefixed policy does not exist.
  -h, --help                    Show this help message

Environment (used when the matching flag is omitted):
  ACCESS_TOKEN    (required) Console access token (alias: BEARER_TOKEN)
  ACCOUNT_ID      Account / organization ID (alias: ORG_ID)
  AGENT_ID        Console agent ID
  CONSOLE_API     API host (alias: API_HOST)
  RESPONSE_FILE

Example:
  export ACCESS_TOKEN='eyJ...'
  $0 --org-id <account_id> \\
     --agent-id <agent_id> \\
     --cluster-name <cluster_name> \\
     --app-name mysql-app --namespaces mysql \\
     --label-selectors 'test=backup' \\
     --policy-name <policy_name>

  # Virtual machines in a namespace that match a label
  $0 --org-id <account_id> \\
     --agent-id <agent_id> \\
     --cluster-name <cluster_name> \\
     --app-name <app_name> --namespaces <namespace> \\
     --app-type virtual-machine-label-selector \\
     --label-selectors 'color=green' \\
     --policy-name <policy_name>

  # policies.txt contains lines such as _daily_snapshots
  # The lookup name is the prefix plus that line: east1_daily_snapshots
  $0 --cluster-name <cluster_name> \\
     --app-name <app_name> --namespaces <namespace> \\
     --policy-name <policy_name> \\
     --site-prefix east1 --policy-file policies.txt
EOF
    exit 1
}


################################################################################
# Parse arguments
################################################################################
# ACCESS_TOKEN / ACCOUNT_ID / CONSOLE_API are the names used in the other
# sections; BEARER_TOKEN / ORG_ID / API_HOST are accepted as aliases.
ACCESS_TOKEN="${ACCESS_TOKEN:-${BEARER_TOKEN:-}}"
ORG_ID="${ORG_ID:-}"
ACCOUNT_ID="${ACCOUNT_ID:-}"
AGENT_ID="${AGENT_ID:-}"
CONSOLE_API="${CONSOLE_API:-${API_HOST:-https://cloudmanager.cloud.netapp.com}}"
RESPONSE_FILE="${RESPONSE_FILE:-/tmp/netapp_create_app_response.json}"
CLUSTER_NAME=""
APP_NAME=""
NAMESPACES=""
LABEL_SELECTORS=""
APP_TYPE=""
SKIP_VM_FREEZE="false"
SIMULTANEOUS_VM_FREEZE="false"
VM_FREEZE_MAX=""
POLICY_NAME=""
SITE_PREFIX=""
POLICY_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --org-id)        ORG_ID="$2";            shift 2 ;;
        --account-id)    ACCOUNT_ID="$2";        shift 2 ;;
        --agent-id)      AGENT_ID="$2";          shift 2 ;;
        --api-host)      CONSOLE_API="$2";          shift 2 ;;
        --response-file) RESPONSE_FILE="$2";     shift 2 ;;
        --cluster-name)  CLUSTER_NAME="$2";      shift 2 ;;
        --app-name)      APP_NAME="$2";          shift 2 ;;
        --namespaces)    NAMESPACES="$2";        shift 2 ;;
        --label-selectors) LABEL_SELECTORS="$2"; shift 2 ;;
        --app-type)      APP_TYPE="$2";          shift 2 ;;
        --skip-vm-freeze) SKIP_VM_FREEZE="true"; shift ;;
        --simultaneous-vm-freeze) SIMULTANEOUS_VM_FREEZE="true"; shift ;;
        --vm-freeze-max) VM_FREEZE_MAX="$2";     shift 2 ;;
        --policy-name)   POLICY_NAME="$2";       shift 2 ;;
        --site-prefix)   SITE_PREFIX="$2";       shift 2 ;;
        --policy-file)   POLICY_FILE="$2";       shift 2 ;;
        -h|--help)       usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

# Account id matches the organization unless a separate account is passed.
[ -z "$ACCOUNT_ID" ] && ACCOUNT_ID="$ORG_ID"
[ -z "$ORG_ID" ] && ORG_ID="$ACCOUNT_ID"
CONSOLE_API="${CONSOLE_API%/}"
BASE_PATH="/backup-recovery/organizations/${ORG_ID}/v1/workloads/k8s"
BASE_URL="${CONSOLE_API}${BASE_PATH}"
APPS_URL="${BASE_URL}/apps"

# Validate required arguments
MISSING=""
[ -z "$ORG_ID" ]        && MISSING="$MISSING --org-id"
[ -z "$AGENT_ID" ]      && MISSING="$MISSING --agent-id"
[ -z "$CLUSTER_NAME" ]  && MISSING="$MISSING --cluster-name"
[ -z "$APP_NAME" ]      && MISSING="$MISSING --app-name"
[ -z "$NAMESPACES" ]    && MISSING="$MISSING --namespaces"
[ -z "$POLICY_NAME" ]   && MISSING="$MISSING --policy-name"

if [ -n "$MISSING" ]; then
    echo -e "${RED}Error: Missing required arguments:${MISSING}${NC}"
    echo ""
    usage
fi

if [ -n "$APP_TYPE" ] && [ "$APP_TYPE" != "virtual-machine-label-selector" ]; then
    echo -e "${RED}Error: --app-type must be virtual-machine-label-selector.${NC}"
    exit 1
fi
if [ "$APP_TYPE" = "virtual-machine-label-selector" ] && [ -z "$LABEL_SELECTORS" ]; then
    echo -e "${RED}Error: virtual-machine-label-selector requires --label-selectors.${NC}"
    exit 1
fi
if [ -n "$VM_FREEZE_MAX" ] && ! [[ "$VM_FREEZE_MAX" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Error: --vm-freeze-max must be a number.${NC}"
    exit 1
fi
if [ "$APP_TYPE" != "virtual-machine-label-selector" ] \
    && { [ "$SKIP_VM_FREEZE" = "true" ] || [ "$SIMULTANEOUS_VM_FREEZE" = "true" ] || [ -n "$VM_FREEZE_MAX" ]; }; then
    echo -e "${RED}Error: VM freeze flags require --app-type virtual-machine-label-selector.${NC}"
    exit 1
fi
if [ -n "$SITE_PREFIX" ] || [ -n "$POLICY_FILE" ]; then
    if [ -z "$SITE_PREFIX" ] || [ -z "$POLICY_FILE" ]; then
        echo -e "${RED}Error: --site-prefix and --policy-file must both be specified.${NC}"
        exit 1
    fi
    if [ ! -f "$POLICY_FILE" ]; then
        echo -e "${RED}Error: policy file '$POLICY_FILE' does not exist.${NC}"
        exit 1
    fi
fi

# ACCESS_TOKEN (or BEARER_TOKEN) must be set in the environment
require_env ACCESS_TOKEN

# Convert comma-separated values to bash arrays
IFS=',' read -ra NS_ARRAY <<< "$NAMESPACES"
IFS=',' read -ra LABEL_ARRAY <<< "$LABEL_SELECTORS"

################################################################################
# Function: Print colored messages
################################################################################
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

################################################################################
# Lookup: Resolve cluster name -> cluster ID
################################################################################
resolve_cluster_id() {
    print_message "$BLUE" "\nLooking up cluster ID for '$CLUSTER_NAME'..."

    local response
    response=$(api_get "${BASE_PATH}/clusters")

    CLUSTER_ID=$(echo "$response" | jq -r --arg name "$CLUSTER_NAME" \
      '[if type == "array" then .[] else (.items[]? // empty) end] | map(select(.name == $name)) | .[0].id // empty')

    if [ -z "$CLUSTER_ID" ]; then
        print_message "$RED" "Error: Could not find a cluster named '$CLUSTER_NAME'."
        print_message "$YELLOW" "Available clusters:"
        echo "$response" | jq -r '[if type == "array" then .[] else (.items[]? // empty) end] | .[] | "  \(.name) (\(.id))"' 2>/dev/null
        return 1
    fi

    print_message "$GREEN" "Resolved cluster ID: $CLUSTER_ID"
    return 0
}

################################################################################
# Lookup: Resolve policy name -> policy ID
################################################################################
resolve_policy_id() {
    print_message "$BLUE" "Looking up policy ID for '$POLICY_NAME'..."

    local response
    response=$(api_get "${BASE_PATH}/kubernetes/policies")

    POLICY_ID=$(echo "$response" | jq -r --arg name "$POLICY_NAME" \
      '[if type == "array" then .[] else (.items[]? // empty) end] | map(select(.policyName == $name)) | .[0].policyId // empty')

    if [ -z "$POLICY_ID" ]; then
        print_message "$RED" "Error: Could not find a policy named '$POLICY_NAME'."
        print_message "$YELLOW" "Available policies:"
        echo "$response" | jq -r '[if type == "array" then .[] else (.items[]? // empty) end] | .[] | "  \(.policyName) (\(.policyId))"' 2>/dev/null
        return 1
    fi

    print_message "$GREEN" "Resolved policy ID: $POLICY_ID"
    return 0
}

################################################################################
# Lookup: Confirm every site-prefixed policy already exists
################################################################################
verify_site_policies() {
    local -a suffixes=()
    local line
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [ -z "$line" ] && continue
        [[ "$line" == \#* ]] && continue
        suffixes+=("$line")
    done < "$POLICY_FILE"

    if [ ${#suffixes[@]} -eq 0 ]; then
        print_message "$RED" "Error: no policies listed in '$POLICY_FILE'."
        return 1
    fi

    print_message "$BLUE" "\nChecking all policies from '$POLICY_FILE' with site prefix '$SITE_PREFIX'..."
    echo "Policies to check:"
    local suffix
    for suffix in "${suffixes[@]}"; do
        echo "  ${SITE_PREFIX}${suffix}"
    done

    local response
    response=$(api_get "${BASE_PATH}/kubernetes/policies")

    if ! echo "$response" | jq -e 'type == "array" or (.items | type == "array")' >/dev/null 2>&1; then
        print_message "$RED" "Error: could not list protection policies."
        echo "$response" | jq '.' 2>/dev/null || echo "$response"
        return 1
    fi

    local -a missing=()
    local -a found=()
    local name policy_id
    for suffix in "${suffixes[@]}"; do
        name="${SITE_PREFIX}${suffix}"
        policy_id=$(echo "$response" | jq -r --arg name "$name" \
          '[if type == "array" then .[] else (.items[]? // empty) end] | map(select(.policyName == $name)) | .[0].policyId // empty')
        if [ -z "$policy_id" ]; then
            missing+=("$name")
        else
            found+=("$name ($policy_id)")
        fi
    done

    if [ ${#found[@]} -gt 0 ]; then
        print_message "$GREEN" "Policies from '$POLICY_FILE' that exist:"
        local found_name
        for found_name in "${found[@]}"; do
            echo "  $found_name"
        done
    else
        print_message "$YELLOW" "No policies from '$POLICY_FILE' exist."
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        print_message "$RED" "Error: the following policies do not exist:"
        local missing_name
        for missing_name in "${missing[@]}"; do
            echo "  $missing_name"
        done
        return 1
    fi

    return 0
}

################################################################################
# STEP 1: Create K8s Application
################################################################################
create_application() {
    print_message "$BLUE" "\n=========================================="
    print_message "$BLUE" "📦 STEP 1: Creating K8s Application"
    print_message "$BLUE" "=========================================="

    echo "Application Name: $APP_NAME"
    echo "Cluster: $CLUSTER_NAME (ID: $CLUSTER_ID)"
    echo "Namespaces: ${NS_ARRAY[*]}"
    [ -n "$APP_TYPE" ] && echo "Application Type: $APP_TYPE"
    [ -n "$LABEL_SELECTORS" ] && echo "Label Selectors: ${LABEL_ARRAY[*]}"
    if [ "$APP_TYPE" = "virtual-machine-label-selector" ]; then
        echo "Skip VM Freeze: $SKIP_VM_FREEZE"
        echo "Simultaneous VM Freeze: $SIMULTANEOUS_VM_FREEZE"
        echo "VM Freeze Max Concurrent: ${VM_FREEZE_MAX:-null}"
    fi
    echo ""

    # Build namespaces JSON array
    NS_JSON=$(printf '%s\n' "${NS_ARRAY[@]}" | jq -R . | jq -s .)

    # Build namespaceScopedResources JSON array
    LABELS_JSON="[]"
    if [ -n "$LABEL_SELECTORS" ]; then
        LABELS_JSON=$(printf '%s\n' "${LABEL_ARRAY[@]}" | jq -R . | jq -s .)
    fi
    NS_SCOPED=$(for ns in "${NS_ARRAY[@]}"; do
        if [ "$APP_TYPE" = "virtual-machine-label-selector" ]; then
            jq -n --arg ns "$ns" --argjson labels "$LABELS_JSON" \
                '{namespace: $ns, namespaceId: "", labelSelectors: $labels}'
        elif [ -n "$LABEL_SELECTORS" ]; then
            jq -n --arg ns "$ns" --argjson labels "$LABELS_JSON" \
                '{namespace: $ns, labelSelectors: $labels}'
        else
            jq -n --arg ns "$ns" '{namespace: $ns}'
        fi
    done | jq -s .)

    # JSON Payload for creating application
    CREATE_PAYLOAD=$(jq -n \
      --arg clusterID "$CLUSTER_ID" \
      --arg clusterName "$CLUSTER_NAME" \
      --arg name "$APP_NAME" \
      --arg appType "$APP_TYPE" \
      --argjson namespaces "$NS_JSON" \
      --argjson nsScoped "$NS_SCOPED" \
      --argjson skipVmFreeze "$SKIP_VM_FREEZE" \
      --argjson simultaneousVmFreeze "$SIMULTANEOUS_VM_FREEZE" \
      --arg vmFreezeMax "$VM_FREEZE_MAX" \
      '{
        state: "",
        resourceCount: 0,
        clusterID: $clusterID,
        protectionState: "unprotected",
        clusterName: $clusterName,
        namespaces: $namespaces,
        name: $name,
        namespaceScopedResources: $nsScoped,
        resourceFilter: null,
        clusterScopedResources: []
      }
      + (if $appType == "virtual-machine-label-selector" then {
          appType: $appType,
          includedVirtualMachines: [],
          vmFreezeSettings: {
            skipVmFreeze: $skipVmFreeze,
            simultaneousVmFreeze: $simultaneousVmFreeze,
            vmFreezeMaxConcurrent: (if $vmFreezeMax == "" then null else ($vmFreezeMax | tonumber) end)
          }
        } else {} end)')

    # Execute CREATE API call
    HTTP_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST "$APPS_URL" \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      -H "Accept: application/json" \
      -H "x-account-id: $ACCOUNT_ID" \
      -H "x-agent-id: $AGENT_ID" \
      -d "$CREATE_PAYLOAD")

    # Extract HTTP status code
    HTTP_STATUS=$(echo "$HTTP_RESPONSE" | grep "HTTP_STATUS" | cut -d: -f2)
    RESPONSE_BODY=$(echo "$HTTP_RESPONSE" | sed '/HTTP_STATUS/d')

    # Save response to file
    echo "$RESPONSE_BODY" > "$RESPONSE_FILE"

    # Check if request was successful
    if [ "$HTTP_STATUS" -ge 200 ] && [ "$HTTP_STATUS" -lt 300 ]; then
        print_message "$GREEN" "✅ Application created successfully!"
        print_message "$GREEN" "HTTP Status: $HTTP_STATUS"
        echo ""
        print_message "$YELLOW" "Response:"
        echo "$RESPONSE_BODY" | jq '.' 2>/dev/null || echo "$RESPONSE_BODY"

        # Extract APP_ID from response (adjust based on actual API response structure)
        APP_ID=$(echo "$RESPONSE_BODY" | jq -r '.id // .appId // .applicationId' 2>/dev/null)

        if [ -z "$APP_ID" ] || [ "$APP_ID" == "null" ]; then
            print_message "$YELLOW" "\n️⚠️  Warning: Could not extract APP_ID from response."
            print_message "$YELLOW" "Please provide the APP_ID manually to protect the application."
            return 1
        fi

        echo ""
        print_message "$GREEN" "📋 Application ID: $APP_ID"
        return 0
    else
        print_message "$RED" "❌ Failed to create application!"
        print_message "$RED" "HTTP Status: $HTTP_STATUS"
        echo ""
        print_message "$RED" "Error Response:"
        echo "$RESPONSE_BODY" | jq '.' 2>/dev/null || echo "$RESPONSE_BODY"
        return 1
    fi
}

################################################################################
# STEP 2: Protect K8s Application
################################################################################
protect_application() {
    local app_id=$1

    print_message "$BLUE" "\n=========================================="
    print_message "$BLUE" "🛡️  STEP 2: Protecting K8s Application"
    print_message "$BLUE" "=========================================="

    echo "Application ID: $app_id"
    echo "Policy Name: $POLICY_NAME (ID: $POLICY_ID)"
    echo ""

    # JSON Payload for protecting application
    PROTECT_PAYLOAD=$(jq -n \
      --arg policyName "$POLICY_NAME" \
      --arg policyId "$POLICY_ID" \
      '{policyName: $policyName, policyId: $policyId}')

    PROTECT_URL="${APPS_URL}/${app_id}/protect"

    # Execute PROTECT API call
    HTTP_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST "$PROTECT_URL" \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      -H "Accept: application/json" \
      -H "x-account-id: $ACCOUNT_ID" \
      -H "x-agent-id: $AGENT_ID" \
      -d "$PROTECT_PAYLOAD")

    # Extract HTTP status code
    HTTP_STATUS=$(echo "$HTTP_RESPONSE" | grep "HTTP_STATUS" | cut -d: -f2)
    RESPONSE_BODY=$(echo "$HTTP_RESPONSE" | sed '/HTTP_STATUS/d')

    # Check if request was successful
    if [ "$HTTP_STATUS" -ge 200 ] && [ "$HTTP_STATUS" -lt 300 ]; then
        print_message "$GREEN" "✅ Application protected successfully!"
        print_message "$GREEN" "HTTP Status: $HTTP_STATUS"
        echo ""
        print_message "$YELLOW" "Response:"
        echo "$RESPONSE_BODY" | jq '.' 2>/dev/null || echo "$RESPONSE_BODY"
        return 0
    else
        print_message "$RED" "❌ Failed to protect application!"
        print_message "$RED" "HTTP Status: $HTTP_STATUS"
        echo ""
        print_message "$RED" "Error Response:"
        echo "$RESPONSE_BODY" | jq '.' 2>/dev/null || echo "$RESPONSE_BODY"
        return 1
    fi
}

################################################################################
# MAIN EXECUTION
################################################################################
main() {
    print_message "$GREEN" "\n╔════════════════════════════════════════════════════════╗"
    print_message "$GREEN" "║ NetApp Console - K8s Application Creation & Protection ║"
    print_message "$GREEN" "╚════════════════════════════════════════════════════════╝"

    if [ -n "$SITE_PREFIX" ]; then
        if ! verify_site_policies; then
            exit 1
        fi
    fi

    # Resolve cluster ID from name
    if ! resolve_cluster_id; then
        exit 1
    fi

    # Resolve policy ID from name
    if ! resolve_policy_id; then
        exit 1
    fi

    # Step 1: Create Application
    if create_application; then
        # Wait a moment for the application to be fully created
        print_message "$YELLOW" "\n⏳ Waiting 3 seconds before protecting application..."
        sleep 3

        # Step 2: Protect Application
        if [ -n "$APP_ID" ] && [ "$APP_ID" != "null" ]; then
            protect_application "$APP_ID"
        else
            print_message "$YELLOW" "\n⚠️  Skipping protection step - APP_ID not available"
            print_message "$YELLOW" "To protect manually, use the APP_ID from the response above"
        fi
    else
        print_message "$RED" "\n❌ Application creation failed. Skipping protection step."
        exit 1
    fi

    print_message "$GREEN" "\n=========================================="
    print_message "$GREEN" "🎉 Script execution completed!"
    print_message "$GREEN" "=========================================="
}

# Run the main function
main
