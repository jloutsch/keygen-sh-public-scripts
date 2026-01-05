#===============================================================================
# Keygen API Policy Creation Script (PowerShell)
#===============================================================================
# This script creates a policy with specific attributes and optional entitlements
# via the Keygen API. Policies define the rules and constraints for licenses.
#
# Requirements:
#   - PowerShell 5.1+ (Windows) or PowerShell Core 7+ (macOS/Linux)
#   - .env file with KEYGEN_API_URL, KEYGEN_ACCOUNT_ID, KEYGEN_API_TOKEN
#
# Usage:
#   Windows:  .\Create-Policy.ps1
#   macOS:    pwsh ./Create-Policy.ps1
#
#===============================================================================

#-------------------------------------------------------------------------------
# CONFIGURATION
#-------------------------------------------------------------------------------

# Set console encoding to UTF-8 for proper character display
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# API request settings
$script:CURL_TIMEOUT = 30    # Maximum time in seconds for API requests
$script:MAX_RETRIES = 3      # Number of retry attempts for failed requests
$script:RETRY_DELAY = 2      # Seconds to wait between retries

#-------------------------------------------------------------------------------
# OUTPUT HELPER FUNCTIONS
#-------------------------------------------------------------------------------
# Color-coded output functions for consistent formatting

function Write-Success { Write-Host $args -ForegroundColor Green }
function Write-Error { Write-Host $args -ForegroundColor Red }
function Write-Warning { Write-Host $args -ForegroundColor Yellow }
function Write-Info { Write-Host $args -ForegroundColor Cyan }

#-------------------------------------------------------------------------------
# ENVIRONMENT LOADING
#-------------------------------------------------------------------------------
# Loads environment variables from .env file if it exists.
# Handles quoted values, comments, and values containing = signs.

$envFile = Join-Path $PSScriptRoot ".env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        # Skip empty lines and comments
        if ($_ -match '^\s*$' -or $_ -match '^\s*#') {
            return
        }
        # Match key=value, handling = in values
        if ($_ -match '^([^=]+)=(.*)$') {
            $name = $matches[1].Trim()
            $value = $matches[2]
            # Remove surrounding quotes if present
            $value = $value -replace '^["'']|["'']$', ''
            if (![string]::IsNullOrWhiteSpace($name)) {
                [Environment]::SetEnvironmentVariable($name, $value, [EnvironmentVariableTarget]::Process)
            }
        }
    }
}

#-------------------------------------------------------------------------------
# ENVIRONMENT VARIABLE VALIDATION
#-------------------------------------------------------------------------------
# Ensures all required Keygen API credentials are configured.

$script:KEYGEN_API_URL = [Environment]::GetEnvironmentVariable("KEYGEN_API_URL")
$script:KEYGEN_ACCOUNT_ID = [Environment]::GetEnvironmentVariable("KEYGEN_ACCOUNT_ID")
$script:KEYGEN_API_TOKEN = [Environment]::GetEnvironmentVariable("KEYGEN_API_TOKEN")

if ([string]::IsNullOrWhiteSpace($script:KEYGEN_API_URL)) {
    Write-Error "Error: KEYGEN_API_URL is not set"
    Write-Host "Please add it to your .env file or set it as an environment variable"
    exit 1
}

if ([string]::IsNullOrWhiteSpace($script:KEYGEN_ACCOUNT_ID)) {
    Write-Error "Error: KEYGEN_ACCOUNT_ID is not set"
    Write-Host "Please add it to your .env file or set it as an environment variable"
    exit 1
}

if ([string]::IsNullOrWhiteSpace($script:KEYGEN_API_TOKEN)) {
    Write-Error "Error: KEYGEN_API_TOKEN is not set"
    Write-Host "Please add it to your .env file or set it as an environment variable"
    exit 1
}

Write-Success "=== Keygen Policy Creation Script ==="
Write-Host ""

#-------------------------------------------------------------------------------
# API REQUEST FUNCTION
#-------------------------------------------------------------------------------
# Makes HTTP requests to the Keygen API with automatic retry logic.
#
# Parameters:
#   Method   - HTTP method (GET, POST, PUT, DELETE)
#   Endpoint - API endpoint (relative to /v1/accounts/{account_id}/)
#   Body     - Request body (optional, for POST/PUT requests)
#
# Returns:
#   API response object or $null on failure
#
# Retry behavior:
#   - Retries on 5xx errors and connection issues
#   - Does not retry on 4xx client errors

function Invoke-KeygenAPI {
    param(
        [string]$Method = "GET",
        [string]$Endpoint,
        [object]$Body = $null
    )

    $headers = @{
        "Authorization" = "Bearer $script:KEYGEN_API_TOKEN"
        "Accept" = "application/vnd.api+json"
        "Content-Type" = "application/vnd.api+json"
    }

    $uri = "$script:KEYGEN_API_URL/v1/accounts/$script:KEYGEN_ACCOUNT_ID/$Endpoint"

    $attempt = 1
    while ($attempt -le $script:MAX_RETRIES) {
        try {
            $params = @{
                Uri = $uri
                Method = $Method
                Headers = $headers
                TimeoutSec = $script:CURL_TIMEOUT
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

            # Client errors (4xx) - don't retry
            if ($statusCode -ge 400 -and $statusCode -lt 500) {
                Write-Error "API request failed (HTTP $statusCode)"
                if ($responseBody) {
                    Write-Host "Response: $responseBody"
                }
                return $null
            }

            # Server errors (5xx) or connection issues - retry with delay
            if ($attempt -lt $script:MAX_RETRIES) {
                Write-Warning "Request failed (HTTP $statusCode), retrying in $($script:RETRY_DELAY)s... (attempt $attempt/$($script:MAX_RETRIES))"
                Start-Sleep -Seconds $script:RETRY_DELAY
            }
            else {
                Write-Error "API request failed after $($script:MAX_RETRIES) attempts (HTTP $statusCode)"
                if ($responseBody) {
                    Write-Host "Response: $responseBody"
                }
                return $null
            }
        }
        $attempt++
    }

    return $null
}

#-------------------------------------------------------------------------------
# PAGINATION HANDLER
#-------------------------------------------------------------------------------
# Fetches all pages of a paginated API endpoint and merges the results.
# Keygen API returns max 100 items per page, so this handles large datasets.
#
# Parameters:
#   Endpoint - API endpoint (e.g., "policies", "products", "entitlements")
#
# Returns:
#   Array of all items from all pages

function Get-AllPages {
    param(
        [string]$Endpoint
    )

    $allData = @()
    $page = 1
    $perPage = 100
    $hasMore = $true

    while ($hasMore) {
        $response = Invoke-KeygenAPI -Endpoint "${Endpoint}?page[number]=${page}&page[size]=${perPage}"

        if (-not $response -or -not $response.data) {
            break
        }

        $allData += $response.data

        # Check if there are more pages by comparing returned count to page size
        if ($response.data.Count -lt $perPage) {
            $hasMore = $false
        }
        else {
            $page++
        }
    }

    return $allData
}

#-------------------------------------------------------------------------------
# INPUT VALIDATION
#-------------------------------------------------------------------------------
# Validates that input is a number within a specified range.
#
# Parameters:
#   Input - Value to validate
#   Min   - Minimum allowed value
#   Max   - Maximum allowed value
#
# Returns:
#   $true if valid, $false if invalid

function Test-ValidNumber {
    param(
        [string]$Input,
        [int]$Min,
        [int]$Max
    )

    $num = 0
    if ([int]::TryParse($Input, [ref]$num)) {
        return ($num -ge $Min -and $num -le $Max)
    }
    return $false
}

#===============================================================================
# MAIN SCRIPT EXECUTION
#===============================================================================

#-------------------------------------------------------------------------------
# Step 1: Select Product
#-------------------------------------------------------------------------------
# Fetches all products and prompts user to select one.
# Policies must be associated with a product.

Write-Info "Step 1: Select Product"
Write-Warning "Fetching available products..."

$products = Get-AllPages -Endpoint "products"

if (-not $products -or $products.Count -eq 0) {
    Write-Error "No products found"
    exit 1
}

# Display available products
Write-Success "Available products:"
for ($i = 0; $i -lt $products.Count; $i++) {
    $product = $products[$i]
    $num = $i + 1
    Write-Host "$num. $($product.attributes.name)"
    Write-Host "   ID: $($product.id)"
    Write-Host ""
}

# Auto-select if only one product, otherwise prompt
if ($products.Count -eq 1) {
    $PRODUCT_ID = $products[0].id
    Write-Success "Using the only available product"
}
else {
    do {
        $selection = Read-Host "Select product number (1-$($products.Count))"
        $valid = Test-ValidNumber -Input $selection -Min 1 -Max $products.Count
        if (-not $valid) {
            Write-Error "Invalid selection. Please enter a number between 1 and $($products.Count)"
        }
    } while (-not $valid)

    $selectedProduct = $products[[int]$selection - 1]
    $PRODUCT_ID = $selectedProduct.id
}

Write-Success "Selected product ID: $PRODUCT_ID"
Write-Host ""

#-------------------------------------------------------------------------------
# Step 2: Policy Details
#-------------------------------------------------------------------------------
# Collects customer name (for policy naming) and optional metadata.

Write-Info "Step 2: Policy Details"
Write-Warning "Enter the customer name for the policy:"
Write-Host "Example format: CUSTOMER NAME Service Contract Test Policy - <entitlement names>"

# Get customer name (required)
do {
    $script:customerName = Read-Host "Customer name"
    if ([string]::IsNullOrWhiteSpace($script:customerName)) {
        Write-Error "Error: Customer name cannot be empty"
    }
} while ([string]::IsNullOrWhiteSpace($script:customerName))

#---------------------------------------------------------------------------
# Metadata collection (optional key-value pairs)
#---------------------------------------------------------------------------
Write-Host ""
Write-Warning "Policy Metadata:"
Write-Host "You can add custom metadata key-value pairs to this policy"
Write-Host "Examples: 'Customer Code', 'Department', 'Contract Number', etc."
Write-Host ""

$script:metadata = @{}

while ($true) {
    $metaKey = Read-Host "Enter metadata key (or press Enter to finish)"

    # Empty input signals end of metadata entry
    if ([string]::IsNullOrWhiteSpace($metaKey)) {
        if ($script:metadata.Count -eq 0) {
            Write-Warning "No metadata added"
        }
        break
    }

    $metaValue = Read-Host "Enter value for '$metaKey'"

    if ([string]::IsNullOrWhiteSpace($metaValue)) {
        Write-Warning "Warning: Empty value, skipping this metadata"
        continue
    }

    $script:metadata[$metaKey] = $metaValue
    Write-Success "Added: $metaKey = $metaValue"
}

#-------------------------------------------------------------------------------
# Step 3: Select Entitlements
#-------------------------------------------------------------------------------
# Fetches all entitlements and allows user to select multiple.
# Entitlements define what features/capabilities a license grants.

Write-Host ""
Write-Info "Step 3: Select Entitlements"
Write-Warning "Fetching available entitlements..."

$entitlements = Get-AllPages -Endpoint "entitlements"

$selectedEntitlements = @()
$entitlementNames = "None"

if ($entitlements -and $entitlements.Count -gt 0) {
    # Display available entitlements
    Write-Success "Available entitlements:"

    for ($i = 0; $i -lt $entitlements.Count; $i++) {
        $entitlement = $entitlements[$i]
        $num = $i + 1
        $name = $entitlement.attributes.name
        $code = if ($entitlement.attributes.code) { $entitlement.attributes.code } else { "No code" }

        Write-Host "$num. $name (Code: $code)"
        Write-Host "   ID: $($entitlement.id)"
        Write-Host ""
    }

    #---------------------------------------------------------------------------
    # Prompt for multi-selection (space-separated numbers)
    #---------------------------------------------------------------------------
    Write-Host ""
    Write-Warning "Select entitlements for this policy:"
    Write-Host "You can select multiple entitlements by entering their numbers separated by spaces"
    Write-Host "Examples: '1 3' for entitlements 1 and 3, or '1 2 4' for entitlements 1, 2, and 4"
    Write-Host "Or enter '0' for no entitlements"
    Write-Host ""

    $entitlementSelection = Read-Host "Enter entitlement numbers (space-separated) or 0 for none"

    if ($entitlementSelection -ne "0") {
        # Parse space-separated selections
        $selections = $entitlementSelection -split '\s+' | Where-Object { $_ -match '^\d+$' }
        $selectedNames = @()

        foreach ($sel in $selections) {
            $index = [int]$sel - 1
            if ($index -ge 0 -and $index -lt $entitlements.Count) {
                $ent = $entitlements[$index]
                $selectedEntitlements += $ent.id

                # Use code for display if available, otherwise use name
                $displayName = if ($ent.attributes.code -and $ent.attributes.code -ne "No code") {
                    $ent.attributes.code
                } else {
                    $ent.attributes.name
                }

                $selectedNames += $displayName
                Write-Success "Selected: $($ent.attributes.name) ($($ent.attributes.code))"
            }
            else {
                Write-Warning "Invalid selection: $sel (skipping)"
            }
        }

        # Join selected names with comma for display
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

#-------------------------------------------------------------------------------
# Step 4: Build and Create Policy
#-------------------------------------------------------------------------------

Write-Host ""
Write-Info "Step 4: Create Policy"

# Build final policy name (includes entitlement names for easy identification)
if ($entitlementNames -ne "None") {
    $policyName = "$($script:customerName) Service Contract Test Policy - $entitlementNames"
}
else {
    $policyName = "$($script:customerName) Service Contract Test Policy"
}

Write-Success "Creating policy: $policyName"

#---------------------------------------------------------------------------
# Build policy payload with predefined attributes
#---------------------------------------------------------------------------
# These settings are optimized for typical software licensing scenarios

$policyAttributes = @{
    name = $policyName
    duration = 31536000                              # 365 days in seconds
    authenticationStrategy = "LICENSE"               # Authenticate using license key
    expirationStrategy = "RESTRICT_ACCESS"           # Block access when expired
    expirationBasis = "FROM_CREATION"                # Expiry calculated from license creation
    renewalBasis = "FROM_EXPIRY"                     # Renewals extend from expiry date
    transferStrategy = "KEEP_EXPIRY"                 # Keep expiry on license transfer
    machineUniquenessStrategy = "UNIQUE_PER_LICENSE" # Each machine unique per license
    machineMatchingStrategy = "MATCH_ANY"            # Match on any machine attribute
    maxMachines = 500                                # Maximum machines per license
    maxProcesses = $null                             # No process limit
    maxCores = $null                                 # No core limit
    floating = $true                                 # Allow floating licenses
    strict = $true                                   # Strict validation mode
    machineLeasingStrategy = "PER_LICENSE"           # Machine leasing per license
    processLeasingStrategy = "PER_MACHINE"           # Process leasing per machine
    overageStrategy = "NO_OVERAGE"                   # No overage allowed
    componentUniquenessStrategy = "UNIQUE_PER_MACHINE"
    componentMatchingStrategy = "MATCH_ANY"
    heartbeatCullStrategy = "DEACTIVATE_DEAD"        # Deactivate machines that stop heartbeating
    heartbeatResurrectionStrategy = "NO_REVIVE"      # Don't auto-revive dead machines
    heartbeatBasis = "FROM_FIRST_PING"               # Heartbeat timing from first ping
    heartbeatDuration = $null                        # No heartbeat duration limit
    requireHeartbeat = $false                        # Heartbeat not required
}

# Add metadata if provided
if ($script:metadata.Count -gt 0) {
    $policyAttributes.metadata = $script:metadata
}

# Build payload according to Keygen API spec (JSON:API format)
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

#---------------------------------------------------------------------------
# Send policy creation request
#---------------------------------------------------------------------------
Write-Warning "Sending request to Keygen API..."
$response = Invoke-KeygenAPI -Method "POST" -Endpoint "policies" -Body $policyPayload

#-------------------------------------------------------------------------------
# Step 5: Handle response and attach entitlements
#-------------------------------------------------------------------------------
if ($response -and $response.data) {
    Write-Success ""
    Write-Success "Policy created successfully!"
    $policyId = $response.data.id
    Write-Success "Policy ID: $policyId"

    #---------------------------------------------------------------------------
    # Attach entitlements if any were selected
    #---------------------------------------------------------------------------
    if ($selectedEntitlements.Count -gt 0) {
        Write-Host ""
        Write-Warning "Attaching entitlements to policy..."

        # Build entitlements payload
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
            Write-Success "Entitlements attached successfully!"
        }
        else {
            Write-Warning "Policy created but failed to attach entitlements"
        }
    }

    #---------------------------------------------------------------------------
    # Display creation summary
    #---------------------------------------------------------------------------
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
    if ($script:metadata.Count -gt 0) {
        Write-Host "Metadata: " -NoNewline
        Write-Info "Yes (custom metadata added)"
    }

    Write-Host ""
    Write-Success "Script completed successfully!"
}
else {
    #---------------------------------------------------------------------------
    # Handle API errors
    #---------------------------------------------------------------------------
    Write-Error "Failed to create policy"
    exit 1
}
