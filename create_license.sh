#!/bin/bash

#===============================================================================
# Keygen API License Creation Script
#===============================================================================
# This script creates a license under an existing policy via the Keygen API.
# It provides interactive prompts for policy selection and license details.
#
# Requirements:
#   - Bash 4.0+ (for associative arrays and mapfile)
#   - Python 3 (for JSON parsing)
#   - curl (for API requests)
#   - .env file with KEYGEN_API_URL, KEYGEN_ACCOUNT_ID, KEYGEN_API_TOKEN
#
# Usage:
#   ./create_license.sh
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
    local http_code

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

        http_code=$(echo "$response" | tail -n 1)
        local response_body=$(echo "$response" | sed '$d')

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
#   $1 - API endpoint (e.g., "policies", "products")
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
# POLICY SELECTION
#-------------------------------------------------------------------------------
# Interactive function to select a policy. Offers three methods:
#   1. Search by name (partial match)
#   2. Enter exact policy ID
#   3. Browse all policies
#
# Sets global variable: selected_policy_id
select_policy() {
    echo -e "${YELLOW}How would you like to find the policy?${NC}"
    echo "1) Search by customer name/policy name"
    echo "2) Enter exact policy ID"
    echo "3) List all policies"

    # Get user's choice with validation
    local search_choice
    while true; do
        read -p "Enter your choice (1-3): " search_choice
        if is_valid_number "$search_choice" 1 3; then
            break
        fi
        echo -e "${RED}Invalid choice. Please enter 1, 2, or 3${NC}"
    done

    case $search_choice in
        1)
            #-------------------------------------------------------------------
            # Search by name - filters policies containing the search term
            #-------------------------------------------------------------------
            read -p "Enter search term (partial name is OK): " search_term
            echo -e "\n${YELLOW}Searching for policies containing '${search_term}'...${NC}"

            # Fetch all policies with pagination
            local response
            response=$(fetch_all_pages "policies")

            if [ $? -ne 0 ]; then
                echo -e "${RED}Failed to fetch policies${NC}"
                exit 1
            fi

            # Parse and filter policies using Python for reliable JSON handling
            # Search term is passed as argument to avoid injection
            local matching_policies
            matching_policies=$(echo "$response" | python3 -c "
import json
import sys

data = json.load(sys.stdin)
search = sys.argv[1].lower() if len(sys.argv) > 1 else ''
matches = []

if 'data' in data:
    for policy in data['data']:
        name = policy.get('attributes', {}).get('name', '')
        metadata = policy.get('attributes', {}).get('metadata', {}) or {}
        customer_code = metadata.get('Customer code', 'N/A')
        if search in name.lower():
            matches.append({
                'id': policy['id'],
                'name': name,
                'customer_code': customer_code,
                'duration': policy.get('attributes', {}).get('duration'),
                'maxMachines': policy.get('attributes', {}).get('maxMachines')
            })

if matches:
    for i, p in enumerate(matches, 1):
        duration_days = p['duration'] // 86400 if p['duration'] else 'Unlimited'
        print(f\"{i}. {p['name']}\")
        print(f\"   ID: {p['id']}\")
        print(f\"   Customer Code: {p['customer_code']}\")
        print(f\"   Duration: {duration_days} days, Max Machines: {p['maxMachines']}\")
        print()

    # Output IDs in parseable format for bash
    for p in matches:
        print(f\"ID:{p['id']}\")
else:
    print('NO_MATCHES')
" "$search_term" 2>/dev/null)

            if [[ "$matching_policies" == *"NO_MATCHES"* ]] || [ -z "$matching_policies" ]; then
                echo -e "${RED}No policies found matching '${search_term}'${NC}"
                exit 1
            fi

            # Display matches (excluding ID: lines)
            echo -e "${GREEN}Found matching policies:${NC}\n"
            echo "$matching_policies" | grep -v "^ID:"

            # Extract policy IDs into array for selection
            local policy_ids=()
            while IFS= read -r line; do
                policy_ids+=("$line")
            done < <(echo "$matching_policies" | grep "^ID:" | cut -d: -f2)
            local num_policies=${#policy_ids[@]}

            # Auto-select if only one match, otherwise prompt
            if [ $num_policies -eq 1 ]; then
                selected_policy_id=${policy_ids[0]}
                echo -e "${GREEN}✓ Using the only matching policy${NC}"
            else
                local selection
                while true; do
                    read -p "Select policy number (1-$num_policies): " selection
                    if is_valid_number "$selection" 1 "$num_policies"; then
                        break
                    fi
                    echo -e "${RED}Invalid selection. Please enter a number between 1 and $num_policies${NC}"
                done
                selected_policy_id=${policy_ids[$((selection-1))]}
            fi
            ;;

        2)
            #-------------------------------------------------------------------
            # Direct ID entry - user provides the exact policy UUID
            #-------------------------------------------------------------------
            read -p "Enter exact policy ID: " selected_policy_id
            if [ -z "$selected_policy_id" ]; then
                echo -e "${RED}Policy ID cannot be empty${NC}"
                exit 1
            fi
            ;;

        3)
            #-------------------------------------------------------------------
            # List all - fetches and displays every policy for browsing
            #-------------------------------------------------------------------
            echo -e "\n${YELLOW}Fetching all policies...${NC}"

            local response
            response=$(fetch_all_pages "policies")

            if [ $? -ne 0 ]; then
                echo -e "${RED}Failed to fetch policies${NC}"
                exit 1
            fi

            # Parse and display all policies
            local all_policies
            all_policies=$(echo "$response" | python3 -c "
import json
import sys

data = json.load(sys.stdin)
policies = []

if 'data' in data:
    for policy in data['data']:
        metadata = policy.get('attributes', {}).get('metadata', {}) or {}
        customer_code = metadata.get('Customer code', 'N/A')
        policies.append({
            'id': policy['id'],
            'name': policy.get('attributes', {}).get('name', 'Unnamed'),
            'customer_code': customer_code,
            'duration': policy.get('attributes', {}).get('duration'),
            'maxMachines': policy.get('attributes', {}).get('maxMachines')
        })

if policies:
    for i, p in enumerate(policies, 1):
        duration_days = p['duration'] // 86400 if p['duration'] else 'Unlimited'
        print(f\"{i}. {p['name']}\")
        print(f\"   ID: {p['id']}\")
        print(f\"   Customer Code: {p['customer_code']}\")
        print(f\"   Duration: {duration_days} days, Max Machines: {p['maxMachines']}\")
        print()

    for p in policies:
        print(f\"ID:{p['id']}\")
else:
    print('NO_POLICIES')
" 2>/dev/null)

            if [[ "$all_policies" == *"NO_POLICIES"* ]] || [ -z "$all_policies" ]; then
                echo -e "${RED}No policies found${NC}"
                exit 1
            fi

            echo -e "${GREEN}Available policies:${NC}\n"
            echo "$all_policies" | grep -v "^ID:"

            # Extract policy IDs into array
            local policy_ids=()
            while IFS= read -r line; do
                policy_ids+=("$line")
            done < <(echo "$all_policies" | grep "^ID:" | cut -d: -f2)
            local num_policies=${#policy_ids[@]}

            local selection
            while true; do
                read -p "Select policy number (1-$num_policies): " selection
                if is_valid_number "$selection" 1 "$num_policies"; then
                    break
                fi
                echo -e "${RED}Invalid selection. Please enter a number between 1 and $num_policies${NC}"
            done
            selected_policy_id=${policy_ids[$((selection-1))]}
            ;;

        *)
            echo -e "${RED}Invalid choice${NC}"
            exit 1
            ;;
    esac

    echo -e "${GREEN}✓ Selected policy ID: ${selected_policy_id}${NC}"
}

#-------------------------------------------------------------------------------
# LICENSE DETAILS COLLECTION
#-------------------------------------------------------------------------------
# Collects license name and optional metadata from the user.
#
# Sets global variables:
#   - license_name: The display name for the license
#   - metadata_keys[]: Array of metadata field names
#   - metadata_values[]: Array of corresponding metadata values
#   - entitlement_summary: Description of entitlement handling
get_license_details() {
    echo -e "\n${YELLOW}License Details:${NC}"

    #---------------------------------------------------------------------------
    # License name input
    #---------------------------------------------------------------------------
    echo -e "${BLUE}Enter a name for this license${NC}"
    echo "This can be an institution and department name, or any identifier"
    echo "Example: 'University of Example - Physics Dept' or 'ACME Corp - Engineering'"

    while true; do
        read -p "License name: " license_name
        if [ -n "$license_name" ]; then
            break
        fi
        echo -e "${RED}Error: License name cannot be empty${NC}"
    done

    #---------------------------------------------------------------------------
    # Metadata collection (optional key-value pairs)
    #---------------------------------------------------------------------------
    echo -e "\n${YELLOW}License Metadata:${NC}"
    echo "You can add custom metadata key-value pairs to this license"
    echo "Examples: 'Customer Code', 'Department', 'License Type', etc."
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

    #---------------------------------------------------------------------------
    # Entitlement information
    #---------------------------------------------------------------------------
    echo -e "\n${BLUE}Note about entitlements:${NC}"
    echo "This license will inherit all entitlements from the selected policy."
    echo "If you need to remove specific entitlements, you can do so via the Keygen UI after creation."

    entitlement_summary="Inherited from policy"
}

#-------------------------------------------------------------------------------
# JSON PAYLOAD BUILDER
#-------------------------------------------------------------------------------
# Builds the license creation API payload using Python for safe JSON encoding.
# This ensures special characters in names/metadata are properly escaped.
#
# Arguments:
#   $1 - Policy ID
#   $2 - License name
#   $3 - Metadata as JSON string
#
# Returns:
#   JSON payload string for the API request
build_license_payload() {
    python3 -c "
import json
import sys

# Read arguments
policy_id = sys.argv[1]
license_name = sys.argv[2]
metadata_json = sys.argv[3] if len(sys.argv) > 3 else '{}'

# Parse metadata
try:
    metadata = json.loads(metadata_json)
except:
    metadata = {}

# Build payload according to Keygen API spec (JSON:API format)
payload = {
    'data': {
        'type': 'licenses',
        'attributes': {
            'name': license_name,
            'protected': False
        },
        'relationships': {
            'policy': {
                'data': {
                    'type': 'policies',
                    'id': policy_id
                }
            }
        }
    }
}

# Add metadata if present
if metadata:
    payload['data']['attributes']['metadata'] = metadata

print(json.dumps(payload))
" "$1" "$2" "$3"
}

#===============================================================================
# MAIN SCRIPT EXECUTION
#===============================================================================

echo -e "${GREEN}=== Keygen License Creation Script ===${NC}\n"

#-------------------------------------------------------------------------------
# Step 1: Select the policy for this license
#-------------------------------------------------------------------------------
select_policy

#-------------------------------------------------------------------------------
# Step 2: Collect license details (name and metadata)
#-------------------------------------------------------------------------------
get_license_details

#-------------------------------------------------------------------------------
# Step 3: Build metadata JSON safely
#-------------------------------------------------------------------------------
# Uses null-separated pairs via environment variable to avoid shell injection
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
# Step 4: Build and send the API request
#-------------------------------------------------------------------------------
json_payload=$(build_license_payload "$selected_policy_id" "$license_name" "$metadata_json")

echo -e "\n${YELLOW}Creating license...${NC}"

response=$(api_request "POST" "licenses" "$json_payload")

# Extract HTTP status code (last line of response)
http_code=$(echo "$response" | tail -n 1)
response_body=$(echo "$response" | sed '$d')

#-------------------------------------------------------------------------------
# Step 5: Handle response and display results
#-------------------------------------------------------------------------------
if [ "$http_code" = "201" ] || [ "$http_code" = "200" ]; then
    echo -e "\n${GREEN}✓ License created successfully!${NC}"

    # Extract and display license details using Python for safe JSON parsing
    license_details=$(echo "$response_body" | python3 -c "
import json
import sys

data = json.load(sys.stdin)
if 'data' in data:
    license = data['data']
    print(f\"ID: {license['id']}\")
    attrs = license.get('attributes', {})
    print(f\"Key: {attrs.get('key', 'N/A')}\")
    if attrs.get('name'):
        print(f\"Name: {attrs['name']}\")
    if attrs.get('expiry'):
        print(f\"Expiry: {attrs['expiry']}\")
    else:
        print(f\"Expiry: Calculated from policy\")
" 2>/dev/null)

    if [ -n "$license_details" ]; then
        echo -e "\n${BLUE}License Details:${NC}"
        echo "$license_details"

        # Extract the license ID for reference
        license_id=$(echo "$license_details" | grep "^ID:" | cut -d' ' -f2)
    fi

    # Note about entitlement inheritance
    echo -e "\n${GREEN}✓ License will inherit all entitlements from the selected policy${NC}"

    #---------------------------------------------------------------------------
    # Display creation summary
    #---------------------------------------------------------------------------
    echo -e "\n${GREEN}══════════════════════════════════════${NC}"
    echo -e "${GREEN}License Creation Summary:${NC}"
    echo -e "${GREEN}══════════════════════════════════════${NC}"
    echo -e "Policy ID: ${BLUE}${selected_policy_id}${NC}"
    echo -e "License Name: ${BLUE}${license_name}${NC}"
    if [ ${#metadata_map[@]} -gt 0 ]; then
        echo -e "Metadata: ${BLUE}Yes (custom metadata added)${NC}"
    fi
    echo -e "Protected: ${BLUE}No${NC}"
    echo -e "Expiry: ${BLUE}Calculated from policy${NC}"
    echo -e "Entitlements: ${BLUE}${entitlement_summary}${NC}"
    echo -e "User: ${BLUE}Not assigned${NC}"
    echo -e "Group: ${BLUE}Not assigned${NC}"

    # Display the license key prominently (this is what the customer uses)
    license_key=$(echo "$response_body" | python3 -c "
import json
import sys
data = json.load(sys.stdin)
if 'data' in data:
    print(data['data'].get('attributes', {}).get('key', 'N/A'))
" 2>/dev/null)

    echo -e "\n${GREEN}LICENSE KEY:${NC}"
    echo -e "${YELLOW}${license_key}${NC}"

else
    #---------------------------------------------------------------------------
    # Handle API errors
    #---------------------------------------------------------------------------
    echo -e "\n${RED}✗ Failed to create license (HTTP ${http_code})${NC}"
    echo -e "\nResponse:"
    echo "$response_body" | python3 -m json.tool 2>/dev/null || echo "$response_body"
    exit 1
fi

echo -e "\n${GREEN}Done!${NC}"
