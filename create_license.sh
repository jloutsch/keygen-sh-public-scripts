#!/bin/bash

# Keygen API License Creation Script
# This script creates a license with policy lookup capabilities

# Color codes for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Load environment variables from .env file if it exists
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

# Configuration - No hardcoded values needed for license creation
# Entitlements are automatically inherited from the selected policy

# Check if required environment variables are set
if [ -z "$KEYGEN_API_URL" ]; then
    echo -e "${RED}Error: KEYGEN_API_URL is not set${NC}"
    echo "Please add it to your .env file or set it as an environment variable"
    exit 1
fi

if [ -z "$KEYGEN_ACCOUNT_ID" ]; then
    echo -e "${RED}Error: KEYGEN_ACCOUNT_ID is not set${NC}"
    echo "Please add it to your .env file or set it as an environment variable"
    exit 1
fi

if [ -z "$KEYGEN_API_TOKEN" ]; then
    echo -e "${RED}Error: KEYGEN_API_TOKEN is not set${NC}"
    echo "Please add it to your .env file or set it as an environment variable"
    exit 1
fi

# Function to search and select a policy
select_policy() {
    echo -e "${YELLOW}How would you like to find the policy?${NC}"
    echo "1) Search by customer name/policy name"
    echo "2) Enter exact policy ID"
    echo "3) List all policies"
    read -p "Enter your choice (1-3): " search_choice
    
    case $search_choice in
        1)
            read -p "Enter search term (partial name is OK): " search_term
            echo -e "\n${YELLOW}Searching for policies containing '${search_term}'...${NC}"
            
            # Fetch all policies and filter by name
            response=$(curl -s -X GET \
                "${KEYGEN_API_URL}/v1/accounts/${KEYGEN_ACCOUNT_ID}/policies?limit=100" \
                -H "Authorization: Bearer ${KEYGEN_API_TOKEN}" \
                -H "Accept: application/vnd.api+json")
            
            # Parse and display matching policies
            matching_policies=$(echo "$response" | python3 -c "
import json
import sys

data = json.load(sys.stdin)
search = '${search_term}'.lower()
matches = []

if 'data' in data:
    for policy in data['data']:
        name = policy.get('attributes', {}).get('name', '')
        metadata = policy.get('attributes', {}).get('metadata', {})
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
    
    # Store IDs for selection
    for p in matches:
        print(f\"ID:{p['id']}\")
else:
    print('NO_MATCHES')
" 2>/dev/null)
            
            if [[ "$matching_policies" == *"NO_MATCHES"* ]] || [ -z "$matching_policies" ]; then
                echo -e "${RED}No policies found matching '${search_term}'${NC}"
                exit 1
            fi
            
            # Display matches and get selection
            echo -e "${GREEN}Found matching policies:${NC}\n"
            echo "$matching_policies" | grep -v "^ID:"
            
            # Extract policy IDs
            policy_ids=($(echo "$matching_policies" | grep "^ID:" | cut -d: -f2))
            num_policies=${#policy_ids[@]}
            
            if [ $num_policies -eq 1 ]; then
                selected_policy_id=${policy_ids[0]}
                echo -e "${GREEN}✓ Using the only matching policy${NC}"
            else
                read -p "Select policy number (1-$num_policies): " selection
                if [[ "$selection" -ge 1 && "$selection" -le $num_policies ]]; then
                    selected_policy_id=${policy_ids[$((selection-1))]}
                else
                    echo -e "${RED}Invalid selection${NC}"
                    exit 1
                fi
            fi
            ;;
            
        2)
            read -p "Enter exact policy ID: " selected_policy_id
            if [ -z "$selected_policy_id" ]; then
                echo -e "${RED}Policy ID cannot be empty${NC}"
                exit 1
            fi
            ;;
            
        3)
            echo -e "\n${YELLOW}Fetching all policies...${NC}"
            
            response=$(curl -s -X GET \
                "${KEYGEN_API_URL}/v1/accounts/${KEYGEN_ACCOUNT_ID}/policies?limit=100" \
                -H "Authorization: Bearer ${KEYGEN_API_TOKEN}" \
                -H "Accept: application/vnd.api+json")
            
            # Parse and display all policies
            all_policies=$(echo "$response" | python3 -c "
import json
import sys

data = json.load(sys.stdin)
policies = []

if 'data' in data:
    for policy in data['data']:
        metadata = policy.get('attributes', {}).get('metadata', {})
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
            
            policy_ids=($(echo "$all_policies" | grep "^ID:" | cut -d: -f2))
            num_policies=${#policy_ids[@]}
            
            read -p "Select policy number (1-$num_policies): " selection
            if [[ "$selection" -ge 1 && "$selection" -le $num_policies ]]; then
                selected_policy_id=${policy_ids[$((selection-1))]}
            else
                echo -e "${RED}Invalid selection${NC}"
                exit 1
            fi
            ;;
            
        *)
            echo -e "${RED}Invalid choice${NC}"
            exit 1
            ;;
    esac
    
    echo -e "${GREEN}✓ Selected policy ID: ${selected_policy_id}${NC}"
}

# Function to get license details
get_license_details() {
    echo -e "\n${YELLOW}License Details:${NC}"

    # License name
    echo -e "${BLUE}Enter a name for this license${NC}"
    echo "This can be an institution and department name, or any identifier"
    echo "Example: 'University of Example - Physics Dept' or 'ACME Corp - Engineering'"
    read -p "License name: " license_name

    if [ -z "$license_name" ]; then
        echo -e "${RED}Error: License name cannot be empty${NC}"
        exit 1
    fi

    # Metadata collection
    echo -e "\n${YELLOW}License Metadata:${NC}"
    echo "You can add custom metadata key-value pairs to this license"
    echo "Examples: 'Customer Code', 'Department', 'License Type', etc."
    echo ""

    # Initialize metadata as empty
    metadata_json=""
    metadata_count=0

    while true; do
        read -p "Enter metadata key (or press Enter to finish): " meta_key

        # If empty, we're done
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

        # Escape quotes in the values
        meta_key_escaped=$(echo "$meta_key" | sed 's/"/\\"/g')
        meta_value_escaped=$(echo "$meta_value" | sed 's/"/\\"/g')

        # Add comma if not first item
        if [ $metadata_count -gt 0 ]; then
            metadata_json+=","
        fi

        metadata_json+="\"${meta_key_escaped}\": \"${meta_value_escaped}\""
        metadata_count=$((metadata_count + 1))

        echo -e "${GREEN}✓ Added: ${meta_key} = ${meta_value}${NC}"
    done

    # Note about entitlements
    echo -e "\n${BLUE}Note about entitlements:${NC}"
    echo "This license will inherit all entitlements from the selected policy."
    echo "If you need to remove specific entitlements, you can do so via the Keygen UI after creation."

    entitlement_summary="Inherited from policy"
}

# Main script execution
echo -e "${GREEN}=== Keygen License Creation Script ===${NC}\n"

# Select policy
select_policy

# Get license details
get_license_details

# Build the JSON payload with conditional metadata
if [ -n "$metadata_json" ]; then
    json_payload=$(cat <<EOF
{
  "data": {
    "type": "licenses",
    "attributes": {
      "name": "${license_name}",
      "protected": false,
      "metadata": {
        ${metadata_json}
      }
    },
    "relationships": {
      "policy": {
        "data": {
          "type": "policies",
          "id": "${selected_policy_id}"
        }
      }
    }
  }
}
EOF
)
else
    json_payload=$(cat <<EOF
{
  "data": {
    "type": "licenses",
    "attributes": {
      "name": "${license_name}",
      "protected": false
    },
    "relationships": {
      "policy": {
        "data": {
          "type": "policies",
          "id": "${selected_policy_id}"
        }
      }
    }
  }
}
EOF
)
fi

# Make the API request to create the license
echo -e "\n${YELLOW}Creating license...${NC}"

response=$(curl -s -w "\n%{http_code}" -X POST \
  "${KEYGEN_API_URL}/v1/accounts/${KEYGEN_ACCOUNT_ID}/licenses" \
  -H "Authorization: Bearer ${KEYGEN_API_TOKEN}" \
  -H "Content-Type: application/vnd.api+json" \
  -H "Accept: application/vnd.api+json" \
  -d "${json_payload}")

# Extract HTTP status code
http_code=$(echo "$response" | tail -n 1)
response_body=$(echo "$response" | sed '$d')

# Check if the request was successful
if [ "$http_code" = "201" ] || [ "$http_code" = "200" ]; then
    echo -e "\n${GREEN}✓ License created successfully!${NC}"
    
    # Extract license details
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
    
    if [ ! -z "$license_details" ]; then
        echo -e "\n${BLUE}License Details:${NC}"
        echo "$license_details"
        
        # Extract the license ID for potential entitlement override
        license_id=$(echo "$license_details" | grep "^ID:" | cut -d' ' -f2)
    fi
    
    # Entitlements are automatically inherited from policy - no additional action needed
    echo -e "\n${GREEN}✓ License will inherit all entitlements from the selected policy${NC}"
    
    echo -e "\n${GREEN}══════════════════════════════════════${NC}"
    echo -e "${GREEN}License Creation Summary:${NC}"
    echo -e "${GREEN}══════════════════════════════════════${NC}"
    echo -e "Policy ID: ${BLUE}${selected_policy_id}${NC}"
    echo -e "License Name: ${BLUE}${license_name}${NC}"
    if [ -n "$metadata_json" ]; then
        echo -e "Metadata: ${BLUE}Yes (custom metadata added)${NC}"
    fi
    echo -e "Protected: ${BLUE}No${NC}"
    echo -e "Expiry: ${BLUE}Calculated from policy${NC}"
    echo -e "Entitlements: ${BLUE}${entitlement_summary}${NC}"
    echo -e "User: ${BLUE}Not assigned${NC}"
    echo -e "Group: ${BLUE}Not assigned${NC}"
    
    # Show the license key prominently
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
    echo -e "\n${RED}✗ Failed to create license (HTTP ${http_code})${NC}"
    echo -e "\nResponse:"
    echo "$response_body" | python3 -m json.tool 2>/dev/null || echo "$response_body"
    exit 1
fi

echo -e "\n${GREEN}Done!${NC}"