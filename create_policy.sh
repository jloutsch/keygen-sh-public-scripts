#!/bin/bash

#===============================================================================
# Keygen API Policy Creation Script
#===============================================================================
# This script creates a policy with specific attributes and optional entitlements
# via the Keygen API. Policies define the rules and constraints for licenses.
#
# Requirements:
#   - Bash 4.0+ (for associative arrays and mapfile)
#   - Python 3 (for JSON parsing)
#   - curl (for API requests)
#   - .env file with KEYGEN_API_URL, KEYGEN_ACCOUNT_ID, KEYGEN_API_TOKEN
#
# Usage:
#   ./create_policy.sh
#
#===============================================================================

# Exit immediately on error, undefined variable, or pipe failure
set -euo pipefail

#-------------------------------------------------------------------------------
# CONFIGURATION
#-------------------------------------------------------------------------------
# Terminal color codes for formatted output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# API request settings
CURL_TIMEOUT=30    # Maximum time in seconds for API requests
MAX_RETRIES=3      # Number of retry attempts for failed requests
RETRY_DELAY=2      # Seconds to wait between retries

#-------------------------------------------------------------------------------
# ENVIRONMENT LOADING
#-------------------------------------------------------------------------------
# Loads environment variables from .env file if it exists.
# Handles quoted values, comments, and values containing = signs.
load_env() {
    local env_file=".env"
    if [ -f "$env_file" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            # Skip empty lines and comments
            [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
            # Extract key and value, handling = in values
            if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
                local key="${BASH_REMATCH[1]}"
                local value="${BASH_REMATCH[2]}"
                # Trim whitespace from key
                key=$(echo "$key" | xargs)
                # Remove surrounding quotes from value if present
                value="${value#\"}"
                value="${value%\"}"
                value="${value#\'}"
                value="${value%\'}"
                # Export the variable
                export "$key=$value"
            fi
        done < "$env_file"
    fi
}

load_env

#-------------------------------------------------------------------------------
# DEPENDENCY CHECKS
#-------------------------------------------------------------------------------
# Verifies that required external commands are available.
check_dependencies() {
    if ! command -v python3 &> /dev/null; then
        echo -e "${RED}Error: python3 is required but not installed${NC}"
        echo "Please install Python 3 to use this script"
        exit 1
    fi

    if ! command -v curl &> /dev/null; then
        echo -e "${RED}Error: curl is required but not installed${NC}"
        exit 1
    fi
}

check_dependencies

#-------------------------------------------------------------------------------
# ENVIRONMENT VARIABLE VALIDATION
#-------------------------------------------------------------------------------
# Ensures all required Keygen API credentials are configured.
if [ -z "${KEYGEN_API_URL:-}" ]; then
    echo -e "${RED}Error: KEYGEN_API_URL is not set${NC}"
    echo "Please add it to your .env file or set it as an environment variable"
    echo "Example: KEYGEN_API_URL=https://api.keygen.sh"
    exit 1
fi

if [ -z "${KEYGEN_ACCOUNT_ID:-}" ]; then
    echo -e "${RED}Error: KEYGEN_ACCOUNT_ID is not set${NC}"
    echo "Please add it to your .env file or set it as an environment variable"
    exit 1
fi

if [ -z "${KEYGEN_API_TOKEN:-}" ]; then
    echo -e "${RED}Error: KEYGEN_API_TOKEN is not set${NC}"
    echo "Please add it to your .env file or set it as an environment variable"
    exit 1
fi

#-------------------------------------------------------------------------------
# API REQUEST FUNCTION
#-------------------------------------------------------------------------------
# Makes HTTP requests to the Keygen API with automatic retry logic.
#
# Arguments:
#   $1 - HTTP method (GET, POST, PUT, DELETE)
#   $2 - API endpoint (relative to /v1/accounts/{account_id}/)
#   $3 - Request body (optional, for POST/PUT requests)
#
# Returns:
#   Response body followed by HTTP status code on the last line
#
# Retry behavior:
#   - Retries on 5xx errors and timeouts
#   - Does not retry on 4xx client errors
api_request() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    local attempt=1
    local response

    while [ $attempt -le $MAX_RETRIES ]; do
        if [ -n "$data" ]; then
            response=$(curl -s -w "\n%{http_code}" \
                --max-time $CURL_TIMEOUT \
                -X "$method" \
                "${KEYGEN_API_URL}/v1/accounts/${KEYGEN_ACCOUNT_ID}/${endpoint}" \
                -H "Authorization: Bearer ${KEYGEN_API_TOKEN}" \
                -H "Content-Type: application/vnd.api+json" \
                -H "Accept: application/vnd.api+json" \
                -d "$data" 2>/dev/null) || true
        else
            response=$(curl -s -w "\n%{http_code}" \
                --max-time $CURL_TIMEOUT \
                -X "$method" \
                "${KEYGEN_API_URL}/v1/accounts/${KEYGEN_ACCOUNT_ID}/${endpoint}" \
                -H "Authorization: Bearer ${KEYGEN_API_TOKEN}" \
                -H "Accept: application/vnd.api+json" 2>/dev/null) || true
        fi

        local http_code=$(echo "$response" | tail -n 1)

        # Success (2xx) or client error (4xx) - don't retry
        if [[ "$http_code" =~ ^[23] ]] || [[ "$http_code" =~ ^4 ]]; then
            echo "$response"
            return 0
        fi

        # Server error (5xx) or timeout - retry with delay
        if [ $attempt -lt $MAX_RETRIES ]; then
            echo -e "${YELLOW}Request failed (HTTP $http_code), retrying in ${RETRY_DELAY}s... (attempt $attempt/$MAX_RETRIES)${NC}" >&2
            sleep $RETRY_DELAY
        fi

        ((attempt++))
    done

    echo "$response"
    return 1
}

#-------------------------------------------------------------------------------
# PAGINATION HANDLER
#-------------------------------------------------------------------------------
# Fetches all pages of a paginated API endpoint and merges the results.
# Keygen API returns max 100 items per page, so this handles large datasets.
#
# Arguments:
#   $1 - API endpoint (e.g., "policies", "products", "entitlements")
#
# Returns:
#   JSON object with all data merged: {"data": [...all items...]}
fetch_all_pages() {
    local endpoint="$1"
    local all_data="[]"
    local page=1
    local per_page=100
    local has_more=true

    while $has_more; do
        local response
        response=$(api_request "GET" "${endpoint}?page[number]=${page}&page[size]=${per_page}")
        local http_code=$(echo "$response" | tail -n 1)
        local response_body=$(echo "$response" | sed '$d')

        if [[ ! "$http_code" =~ ^2 ]]; then
            echo "$response_body"
            return 1
        fi

        # Merge data arrays - pass existing data via stdin to avoid shell interpolation
        all_data=$(printf '%s\n%s' "$all_data" "$response_body" | python3 -c "
import json
import sys

lines = sys.stdin.read().split('\n', 1)
existing = json.loads(lines[0]) if lines[0] else []
new_response = json.loads(lines[1]) if len(lines) > 1 else {}
new_data = new_response.get('data', [])
existing.extend(new_data)
print(json.dumps(existing))
" 2>/dev/null)

        # Check if there are more pages by comparing returned count to page size
        local data_count
        data_count=$(echo "$response_body" | python3 -c "
import json
import sys
data = json.load(sys.stdin)
print(len(data.get('data', [])))
" 2>/dev/null)

        if [ "$data_count" -lt "$per_page" ]; then
            has_more=false
        else
            ((page++))
        fi
    done

    # Return as proper JSON structure
    echo "$all_data" | python3 -c "
import json
import sys
data = json.load(sys.stdin)
print(json.dumps({'data': data}))
" 2>/dev/null
}

#-------------------------------------------------------------------------------
# INPUT VALIDATION
#-------------------------------------------------------------------------------
# Validates that input is a number within a specified range.
#
# Arguments:
#   $1 - Input to validate
#   $2 - Minimum allowed value
#   $3 - Maximum allowed value
#
# Returns:
#   0 if valid, 1 if invalid
is_valid_number() {
    local input="$1"
    local min="$2"
    local max="$3"

    # Check if input is a positive integer
    if ! [[ "$input" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    # Check range
    if [ "$input" -lt "$min" ] || [ "$input" -gt "$max" ]; then
        return 1
    fi

    return 0
}

#-------------------------------------------------------------------------------
# PRODUCT SELECTION
#-------------------------------------------------------------------------------
# Fetches all products and prompts user to select one.
# Policies must be associated with a product.
#
# Sets global variable: selected_product_id
select_product() {
    echo -e "\n${YELLOW}Step 1: Select Product${NC}"
    echo "Fetching available products..."

    local response
    response=$(fetch_all_pages "products")

    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to fetch products${NC}"
        exit 1
    fi

    # Parse and display products using Python for reliable JSON handling
    local products_output
    products_output=$(echo "$response" | python3 -c "
import json
import sys

data = json.load(sys.stdin)
products = []

if 'data' in data:
    for product in data['data']:
        products.append({
            'id': product['id'],
            'name': product.get('attributes', {}).get('name', 'Unnamed Product')
        })

if products:
    for i, p in enumerate(products, 1):
        print(f\"{i}. {p['name']}\")
        print(f\"   ID: {p['id']}\")
        print()

    # Output IDs in parseable format for bash
    for p in products:
        print(f\"ID:{p['id']}\")
else:
    print('NO_PRODUCTS')
" 2>/dev/null)

    if [[ "$products_output" == *"NO_PRODUCTS"* ]] || [ -z "$products_output" ]; then
        echo -e "${RED}No products found in your account${NC}"
        exit 1
    fi

    echo -e "${GREEN}Available products:${NC}\n"
    echo "$products_output" | grep -v "^ID:"

    # Extract product IDs into array
    local product_ids=()
    while IFS= read -r line; do
        product_ids+=("$line")
    done < <(echo "$products_output" | grep "^ID:" | cut -d: -f2)
    local num_products=${#product_ids[@]}

    # Auto-select if only one product, otherwise prompt
    if [ $num_products -eq 1 ]; then
        selected_product_id=${product_ids[0]}
        echo -e "${GREEN}✓ Using the only available product${NC}"
    else
        local selection
        while true; do
            read -p "Select product number (1-$num_products): " selection
            if is_valid_number "$selection" 1 "$num_products"; then
                break
            fi
            echo -e "${RED}Invalid selection. Please enter a number between 1 and $num_products${NC}"
        done
        selected_product_id=${product_ids[$((selection-1))]}
    fi

    echo -e "${GREEN}✓ Selected product ID: ${selected_product_id}${NC}"
}

#-------------------------------------------------------------------------------
# POLICY NAME INPUT
#-------------------------------------------------------------------------------
# Prompts user for the customer name which becomes part of the policy name.
#
# Sets global variable: customer_name
get_policy_name() {
    echo -e "\n${YELLOW}Enter the customer name for the policy:${NC}"
    echo "Example format: CUSTOMER NAME Service Contract Test Policy - <entitlement names>"

    while true; do
        read -p "Customer name: " customer_name
        if [ -n "$customer_name" ]; then
            break
        fi
        echo -e "${RED}Error: Customer name cannot be empty${NC}"
    done
}

#-------------------------------------------------------------------------------
# METADATA COLLECTION
#-------------------------------------------------------------------------------
# Collects optional key-value metadata pairs for the policy.
#
# Sets global variables:
#   - metadata_map: Associative array of metadata key-value pairs
#   - metadata_count: Number of metadata entries
get_metadata() {
    echo -e "\n${YELLOW}Policy Metadata:${NC}"
    echo "You can add custom metadata key-value pairs to this policy"
    echo "Examples: 'Customer Code', 'Department', 'Contract Number', etc."
    echo ""

    # Initialize metadata storage using associative array
    declare -gA metadata_map
    metadata_count=0

    while true; do
        read -p "Enter metadata key (or press Enter to finish): " meta_key

        # Empty input signals end of metadata entry
        if [ -z "$meta_key" ]; then
            if [ $metadata_count -eq 0 ]; then
                echo -e "${YELLOW}No metadata added${NC}"
            fi
            break
        fi

        read -p "Enter value for '$meta_key': " meta_value

        if [ -z "$meta_value" ]; then
            echo -e "${YELLOW}Warning: Empty value, skipping this metadata${NC}"
            continue
        fi

        metadata_map["$meta_key"]="$meta_value"
        metadata_count=$((metadata_count + 1))

        echo -e "${GREEN}✓ Added: ${meta_key} = ${meta_value}${NC}"
    done
}

#-------------------------------------------------------------------------------
# ENTITLEMENT SELECTION
#-------------------------------------------------------------------------------
# Fetches all entitlements and allows user to select multiple.
# Entitlements define what features/capabilities a license grants.
#
# Sets global variables:
#   - selected_entitlements: Array of selected entitlement IDs
#   - entitlement_names: Comma-separated display names for summary
select_entitlements() {
    echo -e "\n${YELLOW}Step 3: Select Entitlements${NC}"
    echo "Fetching available entitlements..."

    local response
    response=$(fetch_all_pages "entitlements")

    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to fetch entitlements${NC}"
        exit 1
    fi

    #---------------------------------------------------------------------------
    # Parse entitlements using temp file to preserve names with spaces
    #---------------------------------------------------------------------------
    local temp_file
    temp_file=$(mktemp)

    echo "$response" | python3 -c "
import json
import sys

data = json.load(sys.stdin)
entitlements = []

if 'data' in data:
    for ent in data['data']:
        attrs = ent.get('attributes', {})
        entitlements.append({
            'id': ent['id'],
            'name': attrs.get('name', 'Unnamed Entitlement'),
            'code': attrs.get('code', 'N/A')
        })

if entitlements:
    # Display formatted list
    for i, e in enumerate(entitlements, 1):
        print(f\"{i}. {e['name']} (Code: {e['code']})\")
        print(f\"   ID: {e['id']}\")
        print()

    # Output structured data (tab-separated to handle spaces in names)
    for e in entitlements:
        print(f\"DATA\\t{e['id']}\\t{e['name']}\\t{e['code']}\")
else:
    print('NO_ENTITLEMENTS')
" > "$temp_file" 2>/dev/null

    local entitlements_output
    entitlements_output=$(cat "$temp_file")

    #---------------------------------------------------------------------------
    # Handle case where no entitlements exist
    #---------------------------------------------------------------------------
    if [[ "$entitlements_output" == *"NO_ENTITLEMENTS"* ]] || [ -z "$entitlements_output" ]; then
        echo -e "${YELLOW}No entitlements found in your account${NC}"
        echo -e "${BLUE}Policy will be created without entitlements${NC}"
        selected_entitlements=()
        entitlement_names="None"
        rm -f "$temp_file"
        return
    fi

    echo -e "${GREEN}Available entitlements:${NC}\n"
    grep -v "^DATA" "$temp_file" || true

    #---------------------------------------------------------------------------
    # Parse entitlement data from temp file (tab-separated format)
    #---------------------------------------------------------------------------
    declare -a entitlement_ids
    declare -a entitlement_name_list
    declare -a entitlement_code_list

    while IFS=$'\t' read -r prefix id name code; do
        if [ "$prefix" = "DATA" ]; then
            entitlement_ids+=("$id")
            entitlement_name_list+=("$name")
            entitlement_code_list+=("$code")
        fi
    done < "$temp_file"

    rm -f "$temp_file"

    local num_entitlements=${#entitlement_ids[@]}

    #---------------------------------------------------------------------------
    # Prompt for multi-selection (space-separated numbers)
    #---------------------------------------------------------------------------
    echo -e "${YELLOW}Enter entitlement numbers (space-separated) or 0 for none:${NC}"
    read -p "Selection: " selection_input

    selected_entitlements=()
    selected_names=()

    if [ "$selection_input" = "0" ]; then
        entitlement_names="None"
        echo -e "${GREEN}✓ No entitlements selected${NC}"
    else
        # Parse space-separated selections
        read -ra selections <<< "$selection_input"

        for selection in "${selections[@]}"; do
            if is_valid_number "$selection" 1 "$num_entitlements"; then
                local idx=$((selection-1))
                selected_entitlements+=("${entitlement_ids[$idx]}")

                # Use code for display if available, otherwise use name
                local name="${entitlement_name_list[$idx]}"
                local code="${entitlement_code_list[$idx]}"

                if [ -n "$code" ] && [ "$code" != "N/A" ]; then
                    selected_names+=("$code")
                else
                    selected_names+=("$name")
                fi

                echo -e "${GREEN}✓ Selected: $name ($code)${NC}"
            else
                echo -e "${YELLOW}⚠ Invalid selection: $selection (skipping)${NC}"
            fi
        done

        # Join selected names with comma for display
        if [ ${#selected_names[@]} -gt 0 ]; then
            entitlement_names=$(IFS=", "; echo "${selected_names[*]}")
        else
            entitlement_names="None"
        fi
    fi
}

#-------------------------------------------------------------------------------
# POLICY PAYLOAD BUILDER
#-------------------------------------------------------------------------------
# Builds the policy creation API payload using Python for safe JSON encoding.
# Includes all the predefined policy attributes for license management.
#
# Arguments:
#   $1 - Product ID
#   $2 - Policy name
#   $3 - Metadata as JSON string
#
# Returns:
#   JSON payload string for the API request
build_policy_payload() {
    local product_id="$1"
    local policy_name="$2"
    local metadata_json="$3"

    python3 -c "
import json
import sys

product_id = sys.argv[1]
policy_name = sys.argv[2]
metadata_json = sys.argv[3] if len(sys.argv) > 3 else '{}'

# Parse metadata
try:
    metadata = json.loads(metadata_json)
except:
    metadata = {}

# Build payload with predefined policy attributes
# These settings are optimized for typical software licensing scenarios
payload = {
    'data': {
        'type': 'policies',
        'attributes': {
            'name': policy_name,
            'duration': 31536000,                          # 365 days in seconds
            'authenticationStrategy': 'LICENSE',          # Authenticate using license key
            'expirationStrategy': 'RESTRICT_ACCESS',      # Block access when expired
            'expirationBasis': 'FROM_CREATION',           # Expiry calculated from license creation
            'renewalBasis': 'FROM_EXPIRY',                # Renewals extend from expiry date
            'transferStrategy': 'KEEP_EXPIRY',            # Keep expiry on license transfer
            'machineUniquenessStrategy': 'UNIQUE_PER_LICENSE',  # Each machine unique per license
            'machineMatchingStrategy': 'MATCH_ANY',       # Match on any machine attribute
            'maxMachines': 500,                           # Maximum machines per license
            'maxProcesses': None,                         # No process limit
            'maxCores': None,                             # No core limit
            'floating': True,                             # Allow floating licenses
            'strict': True,                               # Strict validation mode
            'machineLeasingStrategy': 'PER_LICENSE',      # Machine leasing per license
            'processLeasingStrategy': 'PER_MACHINE',      # Process leasing per machine
            'overageStrategy': 'NO_OVERAGE',              # No overage allowed
            'componentUniquenessStrategy': 'UNIQUE_PER_MACHINE',
            'componentMatchingStrategy': 'MATCH_ANY',
            'heartbeatCullStrategy': 'DEACTIVATE_DEAD',   # Deactivate machines that stop heartbeating
            'heartbeatResurrectionStrategy': 'NO_REVIVE', # Don't auto-revive dead machines
            'heartbeatBasis': 'FROM_FIRST_PING',          # Heartbeat timing from first ping
            'heartbeatDuration': None,                    # No heartbeat duration limit
            'requireHeartbeat': False                     # Heartbeat not required
        },
        'relationships': {
            'product': {
                'data': {
                    'type': 'products',
                    'id': product_id
                }
            }
        }
    }
}

# Add metadata if present
if metadata:
    payload['data']['attributes']['metadata'] = metadata

print(json.dumps(payload))
" "$product_id" "$policy_name" "$metadata_json"
}

#-------------------------------------------------------------------------------
# ENTITLEMENTS PAYLOAD BUILDER
#-------------------------------------------------------------------------------
# Builds the payload to attach entitlements to a policy.
#
# Arguments:
#   $@ - Entitlement IDs to attach
#
# Returns:
#   JSON payload for entitlement attachment API
build_entitlements_payload() {
    python3 -c "
import json
import sys

entitlement_ids = sys.argv[1:]
data = [{'type': 'entitlements', 'id': eid} for eid in entitlement_ids]
print(json.dumps({'data': data}))
" "$@"
}

#===============================================================================
# MAIN SCRIPT EXECUTION
#===============================================================================

echo -e "${GREEN}=== Keygen Policy Creation Script ===${NC}\n"

#-------------------------------------------------------------------------------
# Step 1: Select the product for this policy
#-------------------------------------------------------------------------------
select_product

#-------------------------------------------------------------------------------
# Step 2: Collect policy details (name and metadata)
#-------------------------------------------------------------------------------
echo -e "\n${BLUE}Step 2: Policy Details${NC}"
get_policy_name
get_metadata

#-------------------------------------------------------------------------------
# Step 3: Select entitlements to attach
#-------------------------------------------------------------------------------
select_entitlements

#-------------------------------------------------------------------------------
# Step 4: Build and create the policy
#-------------------------------------------------------------------------------
echo -e "\n${BLUE}Step 4: Create Policy${NC}"

# Build final policy name (includes entitlement names for easy identification)
if [ "$entitlement_names" != "None" ]; then
    policy_name="${customer_name} Service Contract Test Policy - ${entitlement_names}"
else
    policy_name="${customer_name} Service Contract Test Policy"
fi

echo -e "\n${GREEN}Creating policy: ${policy_name}${NC}"

#-------------------------------------------------------------------------------
# Build metadata JSON safely using null-separated pairs
#-------------------------------------------------------------------------------
metadata_json="{}"
if [ ${#metadata_map[@]} -gt 0 ]; then
    # Build METADATA_PAIRS environment variable with null separators
    metadata_pairs=""
    for key in "${!metadata_map[@]}"; do
        if [ -n "$metadata_pairs" ]; then
            metadata_pairs+=$'\x00'
        fi
        metadata_pairs+="${key}=${metadata_map[$key]}"
    done

    metadata_json=$(METADATA_PAIRS="$metadata_pairs" python3 << 'PYEOF'
import json
import os

metadata = {}
pairs = os.environ.get('METADATA_PAIRS', '').split('\x00')
for pair in pairs:
    if '=' in pair:
        key, value = pair.split('=', 1)
        if key:
            metadata[key] = value

print(json.dumps(metadata))
PYEOF
    )
fi

#-------------------------------------------------------------------------------
# Send policy creation request
#-------------------------------------------------------------------------------
json_payload=$(build_policy_payload "$selected_product_id" "$policy_name" "$metadata_json")

echo -e "\n${YELLOW}Sending request to Keygen API...${NC}"

response=$(api_request "POST" "policies" "$json_payload")

# Extract HTTP status code (last line of response)
http_code=$(echo "$response" | tail -n 1)
response_body=$(echo "$response" | sed '$d')

#-------------------------------------------------------------------------------
# Step 5: Handle response and attach entitlements
#-------------------------------------------------------------------------------
if [ "$http_code" = "201" ] || [ "$http_code" = "200" ]; then
    echo -e "\n${GREEN}✓ Policy created successfully!${NC}"

    # Extract the policy ID for entitlement attachment
    policy_id=$(echo "$response_body" | python3 -c "
import json
import sys
data = json.load(sys.stdin)
if 'data' in data:
    print(data['data']['id'])
" 2>/dev/null)

    if [ -n "$policy_id" ]; then
        echo -e "Policy ID: ${GREEN}${policy_id}${NC}"

        #-----------------------------------------------------------------------
        # Attach entitlements if any were selected
        #-----------------------------------------------------------------------
        if [ ${#selected_entitlements[@]} -gt 0 ]; then
            echo -e "\n${YELLOW}Attaching entitlements to policy...${NC}"

            # Build entitlements payload safely
            entitlements_payload=$(build_entitlements_payload "${selected_entitlements[@]}")

            # Send entitlement attachment request
            attach_response=$(api_request "POST" "policies/${policy_id}/entitlements" "$entitlements_payload")

            attach_http_code=$(echo "$attach_response" | tail -n 1)

            if [ "$attach_http_code" = "200" ] || [ "$attach_http_code" = "201" ] || [ "$attach_http_code" = "204" ]; then
                echo -e "${GREEN}✓ Entitlements attached successfully!${NC}"
            else
                echo -e "${YELLOW}⚠ Policy created but failed to attach entitlements (HTTP ${attach_http_code})${NC}"
                attach_response_body=$(echo "$attach_response" | sed '$d')
                echo "Entitlement attachment error:"
                echo "$attach_response_body" | python3 -m json.tool 2>/dev/null || echo "$attach_response_body"
            fi
        fi
    fi

    #---------------------------------------------------------------------------
    # Display creation summary
    #---------------------------------------------------------------------------
    echo -e "\n${GREEN}══════════════════════════════════════${NC}"
    echo -e "${GREEN}Policy Creation Complete!${NC}"
    echo -e "${GREEN}══════════════════════════════════════${NC}"
    echo -e "Name: ${BLUE}${policy_name}${NC}"
    echo -e "Product ID: ${BLUE}${selected_product_id}${NC}"
    echo -e "Entitlements: ${BLUE}${entitlement_names}${NC}"
    echo -e "Policy ID: ${BLUE}${policy_id}${NC}"
    if [ ${#metadata_map[@]} -gt 0 ]; then
        echo -e "Metadata: ${BLUE}Yes (custom metadata added)${NC}"
    fi

    echo -e "\n${GREEN}Script completed successfully!${NC}"
else
    #---------------------------------------------------------------------------
    # Handle API errors
    #---------------------------------------------------------------------------
    echo -e "\n${RED}✗ Failed to create policy (HTTP ${http_code})${NC}"
    echo -e "\nResponse:"
    echo "$response_body" | python3 -m json.tool 2>/dev/null || echo "$response_body"
    exit 1
fi

echo -e "\n${GREEN}Done!${NC}"
