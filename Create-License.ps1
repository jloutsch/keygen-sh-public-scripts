#===============================================================================
# Keygen API License Creation Script (PowerShell)
#===============================================================================
# This script creates a license under an existing policy via the Keygen API.
# It provides interactive prompts for policy selection and license details.
#
# Requirements:
#   - PowerShell 5.1+ (Windows) or PowerShell Core 7+ (macOS/Linux)
#   - .env file with KEYGEN_API_URL, KEYGEN_ACCOUNT_ID, KEYGEN_API_TOKEN
#
# Usage:
#   Windows:  .\Create-License.ps1
#   macOS:    pwsh ./Create-License.ps1
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
# Named to avoid shadowing built-in cmdlets (Write-Error, Write-Warning)

function Write-SuccessMessage { param([Parameter(ValueFromRemainingArguments=$true)]$Message) Write-Host ($Message -join ' ') -ForegroundColor Green }
function Write-ErrorMessage { param([Parameter(ValueFromRemainingArguments=$true)]$Message) Write-Host ($Message -join ' ') -ForegroundColor Red }
function Write-WarningMessage { param([Parameter(ValueFromRemainingArguments=$true)]$Message) Write-Host ($Message -join ' ') -ForegroundColor Yellow }
function Write-InfoMessage { param([Parameter(ValueFromRemainingArguments=$true)]$Message) Write-Host ($Message -join ' ') -ForegroundColor Cyan }

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
            # Remove surrounding quotes if present (handles both single and double quotes)
            if ($value -match '^"(.*)"$' -or $value -match "^'(.*)'$") {
                $value = $matches[1]
            }
            # Validate key contains only safe characters
            if ($name -match '^[a-zA-Z_][a-zA-Z0-9_]*$') {
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
    Write-ErrorMessage "Error: KEYGEN_API_URL is not set"
    Write-Host "Please add it to your .env file or set it as an environment variable"
    exit 1
}

if ([string]::IsNullOrWhiteSpace($script:KEYGEN_ACCOUNT_ID)) {
    Write-ErrorMessage "Error: KEYGEN_ACCOUNT_ID is not set"
    Write-Host "Please add it to your .env file or set it as an environment variable"
    exit 1
}

if ([string]::IsNullOrWhiteSpace($script:KEYGEN_API_TOKEN)) {
    Write-ErrorMessage "Error: KEYGEN_API_TOKEN is not set"
    Write-Host "Please add it to your .env file or set it as an environment variable"
    exit 1
}

# Strip trailing slash from API URL to prevent double slashes
$script:KEYGEN_API_URL = $script:KEYGEN_API_URL.TrimEnd('/')

Write-SuccessMessage "=== Keygen License Creation Script ==="
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
                Write-ErrorMessage "API request failed (HTTP $statusCode)"
                if ($responseBody) {
                    Write-Host "Response: $responseBody"
                }
                return $null
            }

            # Server errors (5xx) or connection issues - retry with delay
            if ($attempt -lt $script:MAX_RETRIES) {
                Write-WarningMessage "Request failed (HTTP $statusCode), retrying in $($script:RETRY_DELAY)s... (attempt $attempt/$($script:MAX_RETRIES))"
                Start-Sleep -Seconds $script:RETRY_DELAY
            }
            else {
                Write-ErrorMessage "API request failed after $($script:MAX_RETRIES) attempts (HTTP $statusCode)"
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
#   Endpoint - API endpoint (e.g., "policies", "products")
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

#-------------------------------------------------------------------------------
# POLICY SELECTION
#-------------------------------------------------------------------------------
# Interactive function to select a policy. Offers three methods:
#   1. Search by name (partial match)
#   2. Enter exact policy ID
#   3. Browse all policies
#
# Returns:
#   Selected policy ID

function Select-Policy {
    Write-WarningMessage "How would you like to find the policy?"
    Write-Host "1) Search by customer name/policy name"
    Write-Host "2) Enter exact policy ID"
    Write-Host "3) List all policies"

    # Get user's choice with validation
    do {
        $searchChoice = Read-Host "Enter your choice (1-3)"
        $valid = Test-ValidNumber -Input $searchChoice -Min 1 -Max 3
        if (-not $valid) {
            Write-ErrorMessage "Invalid choice. Please select 1, 2, or 3"
        }
    } while (-not $valid)

    switch ($searchChoice) {
        "1" {
            #-------------------------------------------------------------------
            # Search by name - filters policies containing the search term
            #-------------------------------------------------------------------
            $searchTerm = Read-Host "Enter search term (partial name is OK)"
            Write-Host ""
            Write-WarningMessage "Searching for policies containing '$searchTerm'..."

            $policies = Get-AllPages -Endpoint "policies"

            if (-not $policies -or $policies.Count -eq 0) {
                Write-ErrorMessage "Failed to fetch policies"
                exit 1
            }

            # Filter policies by search term (case-insensitive)
            $matchingPolicies = @()
            foreach ($policy in $policies) {
                $name = $policy.attributes.name
                if ($name -like "*$searchTerm*") {
                    $matchingPolicies += $policy
                }
            }

            if ($matchingPolicies.Count -eq 0) {
                Write-ErrorMessage "No policies found matching '$searchTerm'"
                exit 1
            }

            # Display matching policies
            Write-SuccessMessage "Found matching policies:"
            Write-Host ""
            for ($i = 0; $i -lt $matchingPolicies.Count; $i++) {
                $policy = $matchingPolicies[$i]
                $num = $i + 1
                $customerCode = if ($policy.attributes.metadata -and $policy.attributes.metadata."Customer code") {
                    $policy.attributes.metadata."Customer code"
                } else {
                    "N/A"
                }
                $duration = if ($policy.attributes.duration) {
                    [math]::Floor($policy.attributes.duration / 86400)
                } else {
                    "Unlimited"
                }

                Write-Host "$num. $($policy.attributes.name)"
                Write-Host "   ID: $($policy.id)"
                Write-Host "   Customer Code: $customerCode"
                Write-Host "   Duration: $duration days, Max Machines: $($policy.attributes.maxMachines)"
                Write-Host ""
            }

            # Auto-select if only one match, otherwise prompt
            if ($matchingPolicies.Count -eq 1) {
                Write-SuccessMessage "Using the only matching policy"
                return $matchingPolicies[0].id
            }
            else {
                do {
                    $selection = Read-Host "Select policy number (1-$($matchingPolicies.Count))"
                    $valid = Test-ValidNumber -Input $selection -Min 1 -Max $matchingPolicies.Count
                    if (-not $valid) {
                        Write-ErrorMessage "Invalid selection. Please enter a number between 1 and $($matchingPolicies.Count)"
                    }
                } while (-not $valid)

                return $matchingPolicies[[int]$selection - 1].id
            }
        }

        "2" {
            #-------------------------------------------------------------------
            # Direct ID entry - user provides the exact policy UUID
            #-------------------------------------------------------------------
            $uuidPattern = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
            do {
                $policyId = Read-Host "Enter exact policy ID (UUID format)"
                if ([string]::IsNullOrWhiteSpace($policyId)) {
                    Write-ErrorMessage "Policy ID cannot be empty"
                }
                elseif ($policyId -notmatch $uuidPattern) {
                    Write-ErrorMessage "Invalid UUID format. Expected format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
                    Write-WarningMessage "Example: a1b2c3d4-e5f6-7890-abcd-ef1234567890"
                    $policyId = $null  # Reset to continue loop
                }
            } while ([string]::IsNullOrWhiteSpace($policyId))

            return $policyId
        }

        "3" {
            #-------------------------------------------------------------------
            # List all - fetches and displays every policy for browsing
            #-------------------------------------------------------------------
            Write-Host ""
            Write-WarningMessage "Fetching all policies..."

            $policies = Get-AllPages -Endpoint "policies"

            if (-not $policies -or $policies.Count -eq 0) {
                Write-ErrorMessage "No policies found"
                exit 1
            }

            Write-SuccessMessage "Available policies:"
            Write-Host ""

            for ($i = 0; $i -lt $policies.Count; $i++) {
                $policy = $policies[$i]
                $num = $i + 1
                $customerCode = if ($policy.attributes.metadata -and $policy.attributes.metadata."Customer code") {
                    $policy.attributes.metadata."Customer code"
                } else {
                    "N/A"
                }
                $duration = if ($policy.attributes.duration) {
                    [math]::Floor($policy.attributes.duration / 86400)
                } else {
                    "Unlimited"
                }

                Write-Host "$num. $($policy.attributes.name)"
                Write-Host "   ID: $($policy.id)"
                Write-Host "   Customer Code: $customerCode"
                Write-Host "   Duration: $duration days, Max Machines: $($policy.attributes.maxMachines)"
                Write-Host ""
            }

            do {
                $selection = Read-Host "Select policy number (1-$($policies.Count))"
                $valid = Test-ValidNumber -Input $selection -Min 1 -Max $policies.Count
                if (-not $valid) {
                    Write-ErrorMessage "Invalid selection. Please enter a number between 1 and $($policies.Count)"
                }
            } while (-not $valid)

            return $policies[[int]$selection - 1].id
        }
    }
}

#-------------------------------------------------------------------------------
# LICENSE DETAILS COLLECTION
#-------------------------------------------------------------------------------
# Collects license name and optional metadata from the user.
#
# Sets script-scoped variables:
#   - $script:licenseName: The display name for the license
#   - $script:metadata: Hashtable of metadata key-value pairs

function Get-LicenseDetails {
    Write-Host ""
    Write-WarningMessage "License Details:"

    #---------------------------------------------------------------------------
    # License name input
    #---------------------------------------------------------------------------
    Write-InfoMessage "Enter a name for this license"
    Write-Host "This can be an institution and department name, or any identifier"
    Write-Host "Example: 'University of Example - Physics Dept' or 'ACME Corp - Engineering'"

    do {
        $script:licenseName = Read-Host "License name"
        if ([string]::IsNullOrWhiteSpace($script:licenseName)) {
            Write-ErrorMessage "Error: License name cannot be empty"
        }
    } while ([string]::IsNullOrWhiteSpace($script:licenseName))

    #---------------------------------------------------------------------------
    # Metadata collection (optional key-value pairs)
    #---------------------------------------------------------------------------
    Write-Host ""
    Write-WarningMessage "License Metadata:"
    Write-Host "You can add custom metadata key-value pairs to this license"
    Write-Host "Examples: 'Customer Code', 'Department', 'License Type', etc."
    Write-Host ""

    $script:metadata = @{}

    while ($true) {
        $metaKey = Read-Host "Enter metadata key (or press Enter to finish)"

        # Empty input signals end of metadata entry
        if ([string]::IsNullOrWhiteSpace($metaKey)) {
            if ($script:metadata.Count -eq 0) {
                Write-WarningMessage "No metadata added"
            }
            break
        }

        $metaValue = Read-Host "Enter value for '$metaKey'"

        if ([string]::IsNullOrWhiteSpace($metaValue)) {
            Write-WarningMessage "Warning: Empty value, skipping this metadata"
            continue
        }

        $script:metadata[$metaKey] = $metaValue
        Write-SuccessMessage "Added: $metaKey = $metaValue"
    }

    #---------------------------------------------------------------------------
    # Entitlement information
    #---------------------------------------------------------------------------
    Write-Host ""
    Write-InfoMessage "Note about entitlements:"
    Write-Host "This license will inherit all entitlements from the selected policy."
    Write-Host "If you need to remove specific entitlements, you can do so via the Keygen UI after creation."
}

#===============================================================================
# MAIN SCRIPT EXECUTION
#===============================================================================

#-------------------------------------------------------------------------------
# Step 1: Select the policy for this license
#-------------------------------------------------------------------------------
$selectedPolicyId = Select-Policy
Write-SuccessMessage "Selected policy ID: $selectedPolicyId"

#-------------------------------------------------------------------------------
# Step 2: Collect license details (name and metadata)
#-------------------------------------------------------------------------------
Get-LicenseDetails

#-------------------------------------------------------------------------------
# Step 3: Build the license payload
#-------------------------------------------------------------------------------
$licenseAttributes = @{
    name = $script:licenseName
    protected = $false
}

# Add metadata if provided
if ($script:metadata.Count -gt 0) {
    $licenseAttributes.metadata = $script:metadata
}

# Build payload according to Keygen API spec (JSON:API format)
$licensePayload = @{
    data = @{
        type = "licenses"
        attributes = $licenseAttributes
        relationships = @{
            policy = @{
                data = @{
                    type = "policies"
                    id = $selectedPolicyId
                }
            }
        }
    }
}

#-------------------------------------------------------------------------------
# Step 4: Confirmation prompt
#-------------------------------------------------------------------------------
Write-Host ""
Write-WarningMessage "Summary:"
Write-Host "  Policy ID: $selectedPolicyId"
Write-Host "  License name: $($script:licenseName)"
if ($script:metadata.Count -gt 0) {
    Write-Host "  Metadata: $($script:metadata.Count) field(s)"
}
Write-Host "  Entitlements: Inherited from policy"
Write-Host ""
$confirm = Read-Host "Create this license? [y/N]"
if ($confirm -notmatch '^[Yy]$') {
    Write-WarningMessage "Cancelled by user"
    exit 0
}

#-------------------------------------------------------------------------------
# Step 5: Send the API request
#-------------------------------------------------------------------------------
Write-Host ""
Write-WarningMessage "Creating license..."

$response = Invoke-KeygenAPI -Method "POST" -Endpoint "licenses" -Body $licensePayload

#-------------------------------------------------------------------------------
# Step 6: Handle response and display results
#-------------------------------------------------------------------------------
if ($response -and $response.data) {
    Write-Host ""
    Write-SuccessMessage "License created successfully!"

    # Extract license details
    $licenseId = $response.data.id
    $licenseKey = $response.data.attributes.key
    $responseLicenseName = $response.data.attributes.name
    $expiry = if ($response.data.attributes.expiry) {
        $response.data.attributes.expiry
    } else {
        "Calculated from policy"
    }

    Write-Host ""
    Write-InfoMessage "License Details:"
    Write-Host "ID: $licenseId"
    Write-Host "Key: $licenseKey"
    Write-Host "Name: $responseLicenseName"
    Write-Host "Expiry: $expiry"

    # Note about entitlement inheritance
    Write-Host ""
    Write-SuccessMessage "License will inherit all entitlements from the selected policy"

    #---------------------------------------------------------------------------
    # Display creation summary
    #---------------------------------------------------------------------------
    Write-Host ""
    Write-SuccessMessage "======================================"
    Write-SuccessMessage "License Creation Summary:"
    Write-SuccessMessage "======================================"
    Write-Host "Policy ID: " -NoNewline
    Write-InfoMessage $selectedPolicyId
    Write-Host "License Name: " -NoNewline
    Write-InfoMessage $script:licenseName
    if ($script:metadata.Count -gt 0) {
        Write-Host "Metadata: " -NoNewline
        Write-InfoMessage "Yes (custom metadata added)"
    }
    Write-Host "Protected: " -NoNewline
    Write-InfoMessage "No"
    Write-Host "Expiry: " -NoNewline
    Write-InfoMessage "Calculated from policy"
    Write-Host "Entitlements: " -NoNewline
    Write-InfoMessage "Inherited from policy"
    Write-Host "User: " -NoNewline
    Write-InfoMessage "Not assigned"
    Write-Host "Group: " -NoNewline
    Write-InfoMessage "Not assigned"
    Write-Host "Next step: " -NoNewline
    Write-InfoMessage "Remove unwanted entitlements via Keygen UI if needed"

    # Display the license key prominently (this is what the customer uses)
    Write-Host ""
    Write-SuccessMessage "LICENSE KEY:"
    Write-WarningMessage $licenseKey

    Write-Host ""
    Write-SuccessMessage "Done!"
}
else {
    #---------------------------------------------------------------------------
    # Handle API errors
    #---------------------------------------------------------------------------
    Write-ErrorMessage "Failed to create license"
    exit 1
}
