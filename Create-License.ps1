# Keygen API License Creation Script (PowerShell Version)
# This script creates a license with policy lookup capabilities

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

Write-Success "=== Keygen License Creation Script ==="
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

# Function to select a policy
function Select-Policy {
    Write-Warning "How would you like to find the policy?"
    Write-Host "1) Search by customer name/policy name"
    Write-Host "2) Enter exact policy ID"
    Write-Host "3) List all policies"
    
    do {
        $searchChoice = Read-Host "Enter your choice (1-3)"
        $valid = $searchChoice -match '^[123]$'
        if (-not $valid) {
            Write-Error "Invalid choice. Please select 1, 2, or 3"
        }
    } while (-not $valid)
    
    switch ($searchChoice) {
        "1" {
            # Search by name
            $searchTerm = Read-Host "Enter search term (partial name is OK)"
            Write-Host ""
            Write-Warning "Searching for policies containing '$searchTerm'..."
            
            $policiesResponse = Invoke-KeygenAPI -Endpoint "policies?limit=100"
            
            if (-not $policiesResponse -or -not $policiesResponse.data) {
                Write-Error "Failed to fetch policies"
                exit 1
            }
            
            # Filter policies by search term
            $matchingPolicies = @()
            foreach ($policy in $policiesResponse.data) {
                $name = $policy.attributes.name
                if ($name -like "*$searchTerm*") {
                    $matchingPolicies += $policy
                }
            }
            
            if ($matchingPolicies.Count -eq 0) {
                Write-Error "No policies found matching '$searchTerm'"
                exit 1
            }
            
            Write-Success "Found matching policies:"
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
            
            if ($matchingPolicies.Count -eq 1) {
                Write-Success "✓ Using the only matching policy"
                return $matchingPolicies[0].id
            }
            else {
                do {
                    $selection = Read-Host "Select policy number (1-$($matchingPolicies.Count))"
                    $valid = $selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $matchingPolicies.Count
                    if (-not $valid) {
                        Write-Error "Invalid selection"
                    }
                } while (-not $valid)
                
                return $matchingPolicies[[int]$selection - 1].id
            }
        }
        
        "2" {
            # Enter exact policy ID
            do {
                $policyId = Read-Host "Enter exact policy ID"
                if ([string]::IsNullOrWhiteSpace($policyId)) {
                    Write-Error "Policy ID cannot be empty"
                }
            } while ([string]::IsNullOrWhiteSpace($policyId))
            
            return $policyId
        }
        
        "3" {
            # List all policies
            Write-Host ""
            Write-Warning "Fetching all policies..."
            
            $policiesResponse = Invoke-KeygenAPI -Endpoint "policies?limit=100"
            
            if (-not $policiesResponse -or -not $policiesResponse.data -or $policiesResponse.data.Count -eq 0) {
                Write-Error "No policies found"
                exit 1
            }
            
            Write-Success "Available policies:"
            Write-Host ""
            
            $policies = @()
            for ($i = 0; $i -lt $policiesResponse.data.Count; $i++) {
                $policy = $policiesResponse.data[$i]
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
                
                $policies += $policy
            }
            
            do {
                $selection = Read-Host "Select policy number (1-$($policies.Count))"
                $valid = $selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $policies.Count
                if (-not $valid) {
                    Write-Error "Invalid selection"
                }
            } while (-not $valid)
            
            return $policies[[int]$selection - 1].id
        }
    }
}

# Function to get license details
function Get-LicenseDetails {
    Write-Host ""
    Write-Warning "License Details:"
    
    # License name
    Write-Info "Enter a name for this license"
    Write-Host "This can be an institution and department name, or any identifier"
    Write-Host "Example: 'University of Example - Physics Dept' or 'ACME Corp - Engineering'"
    
    do {
        $script:licenseName = Read-Host "License name"
        if ([string]::IsNullOrWhiteSpace($script:licenseName)) {
            Write-Error "Error: License name cannot be empty"
        }
    } while ([string]::IsNullOrWhiteSpace($script:licenseName))

    # Metadata collection
    Write-Host ""
    Write-Warning "License Metadata:"
    Write-Host "You can add custom metadata key-value pairs to this license"
    Write-Host "Examples: 'Customer Code', 'Department', 'License Type', etc."
    Write-Host ""

    $script:metadata = @{}

    while ($true) {
        $metaKey = Read-Host "Enter metadata key (or press Enter to finish)"

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
        Write-Success "✓ Added: $metaKey = $metaValue"
    }

    # Note about entitlements
    Write-Host ""
    Write-Info "Note about entitlements:"
    Write-Host "This license will inherit all entitlements from the selected policy."
    Write-Host "If you need to remove specific entitlements, you can do so via the Keygen UI after creation."
}

# Main script execution

# Select policy
$selectedPolicyId = Select-Policy
Write-Success "✓ Selected policy ID: $selectedPolicyId"

# Get license details
Get-LicenseDetails

# Build the license payload
$licenseAttributes = @{
    name = $licenseName
    protected = $false
}

# Add metadata if provided
if ($metadata.Count -gt 0) {
    $licenseAttributes.metadata = $metadata
}

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

# Make the API request to create the license
Write-Host ""
Write-Warning "Creating license..."

$response = Invoke-KeygenAPI -Method "POST" -Endpoint "licenses" -Body $licensePayload

if ($response -and $response.data) {
    Write-Host ""
    Write-Success "✓ License created successfully!"
    
    # Extract license details
    $licenseId = $response.data.id
    $licenseKey = $response.data.attributes.key
    $licenseName = $response.data.attributes.name
    $expiry = if ($response.data.attributes.expiry) { 
        $response.data.attributes.expiry 
    } else { 
        "Calculated from policy" 
    }
    
    Write-Host ""
    Write-Info "License Details:"
    Write-Host "ID: $licenseId"
    Write-Host "Key: $licenseKey"
    Write-Host "Name: $licenseName"
    Write-Host "Expiry: $expiry"
    
    Write-Host ""
    Write-Success "✓ License will inherit all entitlements from the selected policy"
    
    Write-Host ""
    Write-Success "======================================"
    Write-Success "License Creation Summary:"
    Write-Success "======================================"
    Write-Host "Policy ID: " -NoNewline
    Write-Info $selectedPolicyId
    Write-Host "License Name: " -NoNewline
    Write-Info $licenseName
    if ($metadata.Count -gt 0) {
        Write-Host "Metadata: " -NoNewline
        Write-Info "Yes (custom metadata added)"
    }
    Write-Host "Protected: " -NoNewline
    Write-Info "No"
    Write-Host "Expiry: " -NoNewline
    Write-Info "Calculated from policy"
    Write-Host "Entitlements: " -NoNewline
    Write-Info "Inherited from policy"
    Write-Host "User: " -NoNewline
    Write-Info "Not assigned"
    Write-Host "Group: " -NoNewline
    Write-Info "Not assigned"
    Write-Host "Next step: " -NoNewline
    Write-Info "Remove unwanted entitlements via Keygen UI if needed"
    
    Write-Host ""
    Write-Success "LICENSE KEY:"
    Write-Warning $licenseKey
    
    Write-Host ""
    Write-Success "Done!"
}
else {
    Write-Error "Failed to create license"
    exit 1
}