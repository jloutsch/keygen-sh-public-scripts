# Keygen API Policy Creation Script (PowerShell Version)
# This script creates a policy with specific attributes and optional entitlements

# Set console encoding to UTF-8 for proper character display
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Color functions for output
function Write-Success { Write-Host $args -ForegroundColor Green }
function Write-Error { Write-Host $args -ForegroundColor Red }
function Write-Warning { Write-Host $args -ForegroundColor Yellow }
function Write-Info { Write-Host $args -ForegroundColor Cyan }

# Load environment variables from .env file if it exists
$envFile = Join-Path $PSScriptRoot ".env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^([^#=]+)=(.*)$') {
            $name = $matches[1].Trim()
            $value = $matches[2].Trim()
            if (![string]::IsNullOrWhiteSpace($name) -and ![string]::IsNullOrWhiteSpace($value)) {
                [Environment]::SetEnvironmentVariable($name, $value, [EnvironmentVariableTarget]::Process)
            }
        }
    }
}

# Check required environment variables
$KEYGEN_API_URL = [Environment]::GetEnvironmentVariable("KEYGEN_API_URL")
$KEYGEN_ACCOUNT_ID = [Environment]::GetEnvironmentVariable("KEYGEN_ACCOUNT_ID")
$KEYGEN_API_TOKEN = [Environment]::GetEnvironmentVariable("KEYGEN_API_TOKEN")

if ([string]::IsNullOrWhiteSpace($KEYGEN_API_URL)) {
    Write-Error "Error: KEYGEN_API_URL is not set"
    Write-Host "Please add it to your .env file or set it as an environment variable"
    exit 1
}

if ([string]::IsNullOrWhiteSpace($KEYGEN_ACCOUNT_ID)) {
    Write-Error "Error: KEYGEN_ACCOUNT_ID is not set"
    Write-Host "Please add it to your .env file or set it as an environment variable"
    exit 1
}

if ([string]::IsNullOrWhiteSpace($KEYGEN_API_TOKEN)) {
    Write-Error "Error: KEYGEN_API_TOKEN is not set"
    Write-Host "Please add it to your .env file or set it as an environment variable"
    exit 1
}

Write-Success "=== Keygen Policy Creation Script ==="
Write-Host ""

# Function to make API requests
function Invoke-KeygenAPI {
    param(
        [string]$Method = "GET",
        [string]$Endpoint,
        [object]$Body = $null
    )
    
    $headers = @{
        "Authorization" = "Bearer $KEYGEN_API_TOKEN"
        "Accept" = "application/vnd.api+json"
        "Content-Type" = "application/vnd.api+json"
    }
    
    $uri = "$KEYGEN_API_URL/v1/accounts/$KEYGEN_ACCOUNT_ID/$Endpoint"
    
    try {
        $params = @{
            Uri = $uri
            Method = $Method
            Headers = $headers
        }
        
        if ($Body) {
            $params.Body = ($Body | ConvertTo-Json -Depth 10)
        }
        
        $response = Invoke-RestMethod @params
        return $response
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $responseBody = $_.ErrorDetails.Message
        
        Write-Error "API request failed (HTTP $statusCode)"
        if ($responseBody) {
            Write-Host "Response: $responseBody"
        }
        return $null
    }
}

# Step 1: Select Product
Write-Info "Step 1: Select Product"
Write-Warning "Fetching available products..."

$productsResponse = Invoke-KeygenAPI -Endpoint "products?limit=100"

if (-not $productsResponse -or -not $productsResponse.data) {
    Write-Error "No products found"
    exit 1
}

Write-Success "Available products:"
$products = @()
for ($i = 0; $i -lt $productsResponse.data.Count; $i++) {
    $product = $productsResponse.data[$i]
    $num = $i + 1
    Write-Host "$num. $($product.attributes.name)"
    Write-Host "   ID: $($product.id)"
    Write-Host ""
    $products += $product
}

do {
    $selection = Read-Host "Select product number (1-$($products.Count))"
    $valid = $selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $products.Count
    if (-not $valid) {
        Write-Error "Invalid selection. Please enter a number between 1 and $($products.Count)"
    }
} while (-not $valid)

$selectedProduct = $products[[int]$selection - 1]
$PRODUCT_ID = $selectedProduct.id
Write-Success "✓ Selected product ID: $PRODUCT_ID"
Write-Host ""

# Step 2: Policy Details
Write-Info "Step 2: Policy Details"
Write-Warning "Enter the customer name for the policy:"
Write-Host "Example format: CUSTOMER NAME Service Contract Test Policy - <entitlement names>"

do {
    $customerName = Read-Host "Customer name"
    if ([string]::IsNullOrWhiteSpace($customerName)) {
        Write-Error "Error: Customer name cannot be empty"
    }
} while ([string]::IsNullOrWhiteSpace($customerName))

Write-Host ""
Write-Warning "Policy Metadata:"
Write-Host "You can add custom metadata key-value pairs to this policy"
Write-Host "Examples: 'Customer Code', 'Department', 'Contract Number', etc."
Write-Host ""

$metadata = @{}

while ($true) {
    $metaKey = Read-Host "Enter metadata key (or press Enter to finish)"

    if ([string]::IsNullOrWhiteSpace($metaKey)) {
        if ($metadata.Count -eq 0) {
            Write-Warning "No metadata added"
        }
        break
    }

    $metaValue = Read-Host "Enter value for '$metaKey'"

    if ([string]::IsNullOrWhiteSpace($metaValue)) {
        Write-Warning "Warning: Empty value, skipping this metadata"
        continue
    }

    $metadata[$metaKey] = $metaValue
    Write-Success "✓ Added: $metaKey = $metaValue"
}

# Step 3: Select Entitlements
Write-Host ""
Write-Info "Step 3: Select Entitlements"
Write-Warning "Fetching available entitlements..."

$entitlementsResponse = Invoke-KeygenAPI -Endpoint "entitlements?limit=100"

$selectedEntitlements = @()
$entitlementNames = "None"

if ($entitlementsResponse -and $entitlementsResponse.data -and $entitlementsResponse.data.Count -gt 0) {
    Write-Success "Available entitlements:"
    $entitlements = @()
    
    for ($i = 0; $i -lt $entitlementsResponse.data.Count; $i++) {
        $entitlement = $entitlementsResponse.data[$i]
        $num = $i + 1
        $name = $entitlement.attributes.name
        $code = if ($entitlement.attributes.code) { $entitlement.attributes.code } else { "No code" }
        
        Write-Host "$num. $name (Code: $code)"
        Write-Host "   ID: $($entitlement.id)"
        Write-Host ""
        $entitlements += $entitlement
    }
    
    Write-Host ""
    Write-Warning "Select entitlements for this policy:"
    Write-Host "You can select multiple entitlements by entering their numbers separated by spaces"
    Write-Host "Examples: '1 3' for entitlements 1 and 3, or '1 2 4' for entitlements 1, 2, and 4"
    Write-Host "Or enter '0' for no entitlements"
    Write-Host ""
    
    $entitlementSelection = Read-Host "Enter entitlement numbers (space-separated) or 0 for none"
    
    if ($entitlementSelection -ne "0") {
        $selections = $entitlementSelection -split '\s+' | Where-Object { $_ -match '^\d+$' }
        $selectedNames = @()
        
        foreach ($sel in $selections) {
            $index = [int]$sel - 1
            if ($index -ge 0 -and $index -lt $entitlements.Count) {
                $ent = $entitlements[$index]
                $selectedEntitlements += $ent.id
                
                $displayName = if ($ent.attributes.code -and $ent.attributes.code -ne "No code") { 
                    $ent.attributes.code 
                } else { 
                    $ent.attributes.name 
                }
                
                $selectedNames += $displayName
                Write-Success "✓ Selected: $($ent.attributes.name) ($($ent.attributes.code))"
            }
            else {
                Write-Warning "⚠ Invalid selection: $sel (skipping)"
            }
        }
        
        if ($selectedNames.Count -gt 0) {
            $entitlementNames = $selectedNames -join ", "
            Write-Host ""
            Write-Success "Selected entitlements: $entitlementNames"
        }
    }
}
else {
    Write-Warning "No entitlements found - creating policy without entitlements"
}

# Step 4: Build and Create Policy
Write-Host ""
Write-Info "Step 4: Create Policy"

# Build final policy name
if ($entitlementNames -ne "None") {
    $policyName = "$customerName Service Contract Test Policy - $entitlementNames"
}
else {
    $policyName = "$customerName Service Contract Test Policy"
}

Write-Success "Creating policy: $policyName"

# Create the policy payload
$policyAttributes = @{
    name = $policyName
    duration = 31536000
    authenticationStrategy = "LICENSE"
    expirationStrategy = "RESTRICT_ACCESS"
    expirationBasis = "FROM_CREATION"
    renewalBasis = "FROM_EXPIRY"
    transferStrategy = "KEEP_EXPIRY"
    machineUniquenessStrategy = "UNIQUE_PER_LICENSE"
    machineMatchingStrategy = "MATCH_ANY"
    maxMachines = 500
    maxProcesses = $null
    maxCores = $null
    floating = $true
    strict = $true
    machineLeasingStrategy = "PER_LICENSE"
    processLeasingStrategy = "PER_MACHINE"
    overageStrategy = "NO_OVERAGE"
    componentUniquenessStrategy = "UNIQUE_PER_MACHINE"
    componentMatchingStrategy = "MATCH_ANY"
    heartbeatCullStrategy = "DEACTIVATE_DEAD"
    heartbeatResurrectionStrategy = "NO_REVIVE"
    heartbeatBasis = "FROM_FIRST_PING"
    heartbeatDuration = $null
    requireHeartbeat = $false
}

# Add metadata if provided
if ($metadata.Count -gt 0) {
    $policyAttributes.metadata = $metadata
}

$policyPayload = @{
    data = @{
        type = "policies"
        attributes = $policyAttributes
        relationships = @{
            product = @{
                data = @{
                    type = "products"
                    id = $PRODUCT_ID
                }
            }
        }
    }
}

# Make the API request
Write-Warning "Sending request to Keygen API..."
$response = Invoke-KeygenAPI -Method "POST" -Endpoint "policies" -Body $policyPayload

if ($response -and $response.data) {
    Write-Success ""
    Write-Success "✓ Policy created successfully!"
    $policyId = $response.data.id
    Write-Success "Policy ID: $policyId"
    
    # Attach entitlements if any were selected
    if ($selectedEntitlements.Count -gt 0) {
        Write-Host ""
        Write-Warning "Attaching entitlements to policy..."
        
        $entitlementsData = @()
        foreach ($entId in $selectedEntitlements) {
            $entitlementsData += @{
                type = "entitlements"
                id = $entId
            }
        }
        
        $attachPayload = @{ data = $entitlementsData }
        $attachResponse = Invoke-KeygenAPI -Method "POST" -Endpoint "policies/$policyId/entitlements" -Body $attachPayload
        
        if ($attachResponse) {
            Write-Success "✓ Entitlements attached successfully!"
        }
        else {
            Write-Warning "⚠ Policy created but failed to attach entitlements"
        }
    }
    
    Write-Host ""
    Write-Success "======================================"
    Write-Success "Policy Creation Complete!"
    Write-Success "======================================"
    Write-Host "Name: " -NoNewline
    Write-Info $policyName
    Write-Host "Product ID: " -NoNewline
    Write-Info $PRODUCT_ID
    Write-Host "Entitlements: " -NoNewline
    Write-Info $entitlementNames
    Write-Host "Policy ID: " -NoNewline
    Write-Info $policyId
    if ($metadata.Count -gt 0) {
        Write-Host "Metadata: " -NoNewline
        Write-Info "Yes (custom metadata added)"
    }
    
    Write-Host ""
    Write-Success "Script completed successfully!"
}
else {
    Write-Error "Failed to create policy"
    exit 1
}