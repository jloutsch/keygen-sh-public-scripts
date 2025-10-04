#!/bin/bash

# Keygen API Policy Creation Script
# This script creates a policy with specific attributes and optional entitlements

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

# Check if required environment variables are set
if [ -z "$KEYGEN_API_URL" ]; then
    echo -e "${RED}Error: KEYGEN_API_URL is not set${NC}"
    echo "Please add it to your .env file or set it as an environment variable"
    echo "Example: KEYGEN_API_URL=https://api.keygen.sh"
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

# Function to select a product
select_product() {
    echo -e "\n${YELLOW}Step 1: Select Product${NC}"
    echo "Fetching available products..."

    response=$(curl -s -X GET \
        "${KEYGEN_API_URL}/v1/accounts/${KEYGEN_ACCOUNT_ID}/products?limit=100" \
        -H "Authorization: Bearer ${KEYGEN_API_TOKEN}" \
        -H "Accept: application/vnd.api+json")

    # Parse and display products
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

    product_ids=($(echo "$products_output" | grep "^ID:" | cut -d: -f2))
    num_products=${#product_ids[@]}

    if [ $num_products -eq 1 ]; then
        selected_product_id=${product_ids[0]}
        echo -e "${GREEN}✓ Using the only available product${NC}"
    else
        read -p "Select product number (1-$num_products): " selection
        if [[ "$selection" -ge 1 && "$selection" -le $num_products ]]; then
            selected_product_id=${product_ids[$((selection-1))]}
        else
            echo -e "${RED}Invalid selection${NC}"
            exit 1
        fi
    fi

    echo -e "${GREEN}✓ Selected product ID: ${selected_product_id}${NC}"
}

# Function to prompt for policy name
get_policy_name() {
    echo -e "\n${YELLOW}Enter the customer name for the policy:${NC}"
    echo "Example format: CUSTOMER NAME Service Contract Test Policy - <entitlement names>"
    read -p "Customer name: " customer_name
    
    if [ -z "$customer_name" ]; then
        echo -e "${RED}Error: Customer name cannot be empty${NC}"
        exit 1
    fi
}

# Function to collect metadata
get_metadata() {
    echo -e "\n${YELLOW}Policy Metadata:${NC}"
    echo "You can add custom metadata key-value pairs to this policy"
    echo "Examples: 'Customer Code', 'Department', 'Contract Number', etc."
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
}

# Function to fetch and select entitlements
select_entitlements() {
    echo -e "\n${YELLOW}Step 3: Select Entitlements${NC}"
    echo "Fetching available entitlements..."

    response=$(curl -s -X GET \
        "${KEYGEN_API_URL}/v1/accounts/${KEYGEN_ACCOUNT_ID}/entitlements?limit=100" \
        -H "Authorization: Bearer ${KEYGEN_API_TOKEN}" \
        -H "Accept: application/vnd.api+json")

    # Parse and display entitlements
    entitlements_output=$(echo "$response" | python3 -c "
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
    for i, e in enumerate(entitlements, 1):
        print(f\"{i}. {e['name']} (Code: {e['code']})\")
        print(f\"   ID: {e['id']}\")
        print()

    for e in entitlements:
        print(f\"ID:{e['id']}\")
        print(f\"NAME:{e['name']}\")
        print(f\"CODE:{e['code']}\")
else:
    print('NO_ENTITLEMENTS')
" 2>/dev/null)

    if [[ "$entitlements_output" == *"NO_ENTITLEMENTS"* ]] || [ -z "$entitlements_output" ]; then
        echo -e "${YELLOW}No entitlements found in your account${NC}"
        echo -e "${BLUE}Policy will be created without entitlements${NC}"
        selected_entitlements=()
        entitlement_names="None"
        return
    fi

    echo -e "${GREEN}Available entitlements:${NC}\n"
    echo "$entitlements_output" | grep -v "^ID:" | grep -v "^NAME:" | grep -v "^CODE:"

    entitlement_ids=($(echo "$entitlements_output" | grep "^ID:" | cut -d: -f2))
    entitlement_name_list=($(echo "$entitlements_output" | grep "^NAME:" | cut -d: -f2-))
    entitlement_code_list=($(echo "$entitlements_output" | grep "^CODE:" | cut -d: -f2))
    num_entitlements=${#entitlement_ids[@]}

    echo -e "${YELLOW}Enter entitlement numbers (space-separated) or 0 for none:${NC}"
    read -p "Selection: " -a selections

    selected_entitlements=()
    selected_names=()

    if [ "${selections[0]}" = "0" ]; then
        entitlement_names="None"
        echo -e "${GREEN}✓ No entitlements selected${NC}"
    else
        for selection in "${selections[@]}"; do
            if [[ "$selection" -ge 1 && "$selection" -le $num_entitlements ]]; then
                idx=$((selection-1))
                selected_entitlements+=("${entitlement_ids[$idx]}")

                # Get the name for this entitlement
                name=$(echo "$entitlements_output" | grep -A1 "^ID:${entitlement_ids[$idx]}$" | grep "^NAME:" | cut -d: -f2-)
                code=$(echo "$entitlements_output" | grep -A2 "^ID:${entitlement_ids[$idx]}$" | grep "^CODE:" | cut -d: -f2)

                if [ ! -z "$code" ] && [ "$code" != "N/A" ]; then
                    selected_names+=("$code")
                else
                    selected_names+=("$name")
                fi

                echo -e "${GREEN}✓ Selected: $name ($code)${NC}"
            else
                echo -e "${RED}Invalid selection: $selection${NC}"
                exit 1
            fi
        done

        # Join selected names with comma
        entitlement_names=$(IFS=", "; echo "${selected_names[*]}")
    fi
}

# Main script execution
echo -e "${GREEN}=== Keygen Policy Creation Script ===${NC}\n"

# Step 1: Select Product
select_product

# Step 2: Policy Details
echo -e "\n${BLUE}Step 2: Policy Details${NC}"
get_policy_name
get_metadata

# Step 3: Select Entitlements
select_entitlements

# Step 4: Create Policy
echo -e "\n${BLUE}Step 4: Create Policy${NC}"

# Build final policy name
if [ "$entitlement_names" != "None" ]; then
    policy_name="${customer_name} Service Contract Test Policy - ${entitlement_names}"
else
    policy_name="${customer_name} Service Contract Test Policy"
fi

echo -e "\n${GREEN}Creating policy: ${policy_name}${NC}"

# Create the JSON payload with conditional metadata
if [ -n "$metadata_json" ]; then
    json_payload=$(cat <<EOF
{
  "data": {
    "type": "policies",
    "attributes": {
      "name": "${policy_name}",
      "duration": 31536000,
      "authenticationStrategy": "LICENSE",
      "expirationStrategy": "RESTRICT_ACCESS",
      "expirationBasis": "FROM_CREATION",
      "renewalBasis": "FROM_EXPIRY",
      "transferStrategy": "KEEP_EXPIRY",
      "machineUniquenessStrategy": "UNIQUE_PER_LICENSE",
      "machineMatchingStrategy": "MATCH_ANY",
      "maxMachines": 500,
      "maxProcesses": null,
      "maxCores": null,
      "floating": true,
      "strict": true,
      "machineLeasingStrategy": "PER_LICENSE",
      "processLeasingStrategy": "PER_MACHINE",
      "overageStrategy": "NO_OVERAGE",
      "componentUniquenessStrategy": "UNIQUE_PER_MACHINE",
      "componentMatchingStrategy": "MATCH_ANY",
      "heartbeatCullStrategy": "DEACTIVATE_DEAD",
      "heartbeatResurrectionStrategy": "NO_REVIVE",
      "heartbeatBasis": "FROM_FIRST_PING",
      "heartbeatDuration": null,
      "requireHeartbeat": false,
      "metadata": {
        ${metadata_json}
      }
    },
    "relationships": {
      "product": {
        "data": {
          "type": "products",
          "id": "${selected_product_id}"
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
    "type": "policies",
    "attributes": {
      "name": "${policy_name}",
      "duration": 31536000,
      "authenticationStrategy": "LICENSE",
      "expirationStrategy": "RESTRICT_ACCESS",
      "expirationBasis": "FROM_CREATION",
      "renewalBasis": "FROM_EXPIRY",
      "transferStrategy": "KEEP_EXPIRY",
      "machineUniquenessStrategy": "UNIQUE_PER_LICENSE",
      "machineMatchingStrategy": "MATCH_ANY",
      "maxMachines": 500,
      "maxProcesses": null,
      "maxCores": null,
      "floating": true,
      "strict": true,
      "machineLeasingStrategy": "PER_LICENSE",
      "processLeasingStrategy": "PER_MACHINE",
      "overageStrategy": "NO_OVERAGE",
      "componentUniquenessStrategy": "UNIQUE_PER_MACHINE",
      "componentMatchingStrategy": "MATCH_ANY",
      "heartbeatCullStrategy": "DEACTIVATE_DEAD",
      "heartbeatResurrectionStrategy": "NO_REVIVE",
      "heartbeatBasis": "FROM_FIRST_PING",
      "heartbeatDuration": null,
      "requireHeartbeat": false
    },
    "relationships": {
      "product": {
        "data": {
          "type": "products",
          "id": "${selected_product_id}"
        }
      }
    }
  }
}
EOF
)
fi

# Make the API request
echo -e "\n${YELLOW}Sending request to Keygen API...${NC}"

response=$(curl -s -w "\n%{http_code}" -X POST \
  "${KEYGEN_API_URL}/v1/accounts/${KEYGEN_ACCOUNT_ID}/policies" \
  -H "Authorization: Bearer ${KEYGEN_API_TOKEN}" \
  -H "Content-Type: application/vnd.api+json" \
  -H "Accept: application/vnd.api+json" \
  -d "${json_payload}")

# Extract HTTP status code
http_code=$(echo "$response" | tail -n 1)
response_body=$(echo "$response" | sed '$d')

# Check if the request was successful
if [ "$http_code" = "201" ] || [ "$http_code" = "200" ]; then
    echo -e "\n${GREEN}✓ Policy created successfully!${NC}"
    
    # Extract the policy ID
    policy_id=$(echo "$response_body" | python3 -c "
import json
import sys
data = json.load(sys.stdin)
if 'data' in data:
    print(data['data']['id'])
" 2>/dev/null)
    
    if [ ! -z "$policy_id" ]; then
        echo -e "Policy ID: ${GREEN}${policy_id}${NC}"
        
        # Attach entitlements if any were selected
        if [ ${#selected_entitlements[@]} -gt 0 ]; then
            echo -e "\n${YELLOW}Attaching entitlements to policy...${NC}"
            
            # Build entitlements JSON array for attachment
            entitlements_data="["
            for i in "${!selected_entitlements[@]}"; do
                if [ $i -gt 0 ]; then
                    entitlements_data+=","
                fi
                entitlements_data+="{\"type\":\"entitlements\",\"id\":\"${selected_entitlements[$i]}\"}"
            done
            entitlements_data+="]"
            
            # Attach entitlements to the policy
            attach_response=$(curl -s -w "\n%{http_code}" -X POST \
              "${KEYGEN_API_URL}/v1/accounts/${KEYGEN_ACCOUNT_ID}/policies/${policy_id}/entitlements" \
              -H "Authorization: Bearer ${KEYGEN_API_TOKEN}" \
              -H "Content-Type: application/vnd.api+json" \
              -H "Accept: application/vnd.api+json" \
              -d "{\"data\":${entitlements_data}}")
            
            attach_http_code=$(echo "$attach_response" | tail -n 1)
            
            if [ "$attach_http_code" = "200" ] || [ "$attach_http_code" = "201" ]; then
                echo -e "${GREEN}✓ Entitlements attached successfully!${NC}"
            else
                echo -e "${YELLOW}⚠ Policy created but failed to attach entitlements (HTTP ${attach_http_code})${NC}"
                attach_response_body=$(echo "$attach_response" | sed '$d')
                echo "Entitlement attachment error:"
                echo "$attach_response_body" | python3 -m json.tool 2>/dev/null || echo "$attach_response_body"
            fi
        fi
    fi
    
    echo -e "\n${GREEN}══════════════════════════════════════${NC}"
    echo -e "${GREEN}Policy Creation Complete!${NC}"
    echo -e "${GREEN}══════════════════════════════════════${NC}"
    echo -e "Name: ${BLUE}${policy_name}${NC}"
    echo -e "Product ID: ${BLUE}${selected_product_id}${NC}"
    echo -e "Entitlements: ${BLUE}${entitlement_names}${NC}"
    echo -e "Policy ID: ${BLUE}${policy_id}${NC}"
    if [ -n "$metadata_json" ]; then
        echo -e "Metadata: ${BLUE}Yes (custom metadata added)${NC}"
    fi
    
    echo -e "\n${GREEN}Script completed successfully!${NC}"
else
    echo -e "\n${RED}✗ Failed to create policy (HTTP ${http_code})${NC}"
    echo -e "\nResponse:"
    echo "$response_body" | python3 -m json.tool 2>/dev/null || echo "$response_body"
    exit 1
fi

echo -e "\n${GREEN}Done!${NC}"