# Keygen API Scripts

This repository contains bash scripts for creating policies and licenses via the Keygen API.

## Prerequisites

- **Keygen Account**: Access to a Keygen Cloud account or self-hosted instance
- **API Token**: A valid API token with appropriate permissions
- **Python 3**: Required for JSON parsing (pre-installed on most systems)
- **curl**: For API requests (pre-installed on most systems)
- **bash**: Unix shell (available on macOS, Linux, and Windows with WSL)

## Setup

### 1. Environment Configuration

Create a `.env` file in the same directory as the scripts:

```bash
# Your Keygen API configuration
KEYGEN_API_URL=https://api.keygen.sh
KEYGEN_ACCOUNT_ID=your-account-id-here
KEYGEN_API_TOKEN=your-api-token-here
```

**To find these values:**
- **API URL**: `https://api.keygen.sh` for Keygen Cloud, or your custom domain for self-hosted
- **Account ID**: Found in your Keygen dashboard account settings
- **API Token**: Generate from Settings → Tokens in your Keygen dashboard

### 2. Make Scripts Executable

```bash
chmod +x create_policy_v2.sh
chmod +x create_license.sh
```

## Scripts Overview

### 📋 Policy Creation Script (`create_policy_v2.sh`)

Creates policies with predefined attributes and optional entitlements.

**Features:**
- Interactive product selection from your account
- Dynamic entitlement fetching and multi-selection
- Customer code metadata
- Predefined policy attributes optimized for licensing

**Policy Attributes:**
- Duration: 365 days (31,536,000 seconds)
- Max Machines: 500
- Authentication: LICENSE
- Floating: Yes
- And many more predefined settings

### 📄 License Creation Script (`create_license.sh`)

Creates licenses under existing policies with automatic entitlement inheritance.

**Features:**
- Policy search by name or browse all policies
- Institution/department name support
- Customer code metadata
- Automatic entitlement inheritance from selected policy
- Note about removing unwanted entitlements via UI

## Usage Guide

### Creating a Policy

1. **Run the script:**
   ```bash
   ./create_policy_v2.sh
   ```

2. **Follow the interactive prompts:**
   - **Step 1**: Select a product from your account
   - **Step 2**: Enter customer name and customer code
   - **Step 3**: Select entitlements (multiple selections supported)
   - **Step 4**: Policy creation and entitlement attachment

3. **Example interaction:**
   ```
   Step 1: Select Product
   1. My Software Product
      ID: 12345678-1234-5678-9abc-def012345678
   
   Select product number (1-1): 1
   
   Step 2: Policy Details
   Customer name: ACME Corporation
   Customer code: ACME001
   
   Step 3: Select Entitlements
   Available entitlements:
   1. Basic Access (Code: BASIC)
   2. Advanced Features (Code: ADVANCED)
   3. Premium Support (Code: PREMIUM)
   4. API Access (Code: API)
   5. Analytics Dashboard (Code: ANALYTICS)

   Enter entitlement numbers (space-separated) or 0 for none: 1 2 3
   ✓ Selected: Basic Access (BASIC)
   ✓ Selected: Advanced Features (ADVANCED)
   ✓ Selected: Premium Support (PREMIUM)

   Examples of valid inputs:
   - Single: "1" for Basic Access only
   - Multiple: "1 2 4" for Basic, Advanced, and API Access
   - All: "1 2 3 4 5" for all entitlements
   - None: "0" for no entitlements
   ```

### Creating a License

1. **Run the script:**
   ```bash
   ./create_license.sh
   ```

2. **Follow the interactive prompts:**
   - **Policy Selection**: Search, browse, or enter exact policy ID
   - **License Details**: Enter name (can be institution/department) and customer code
   - **Automatic**: Entitlements inherited from policy

3. **Example interaction:**
   ```
   How would you like to find the policy?
   1) Search by customer name/policy name
   2) Enter exact policy ID
   3) List all policies
   Enter your choice (1-3): 1
   
   Enter search term: ACME
   
   Found matching policies:
   1. ACME Corporation Service Contract Test Policy - BASIC, ADVANCED, PREMIUM
      ID: 87654321-4321-8765-dcba-210fedcba987
      Customer Code: ACME001
   
   License name: ACME Corp - Engineering Department
   Customer code: ACME001-ENG
   ```

## Policy vs License Entitlements

### Understanding Entitlement Inheritance

- **Policy Entitlements**: Automatically inherited by ALL licenses under that policy
- **License Entitlements**: Additional entitlements that can be added to individual licenses
- **Removal**: Policy entitlements CANNOT be removed from licenses via API - only through the Keygen UI

### Recommended Workflow

1. **Create policies with ALL possible entitlements** your customer might need
2. **Create licenses** under those policies (inherits all entitlements)  
3. **Remove unwanted entitlements** via the Keygen UI for specific licenses

This approach keeps policy management simple while providing per-license flexibility.

## File Structure

```
keygen-api/
├── .env                    # Environment configuration
├── create_policy_v2.sh     # Policy creation script
├── create_license.sh       # License creation script
├── README.md              # This documentation
└── keygen.md              # Claude Code development guide
```

## Troubleshooting

### Common Issues

**"Bad request, type mismatch (received string expected UUID string)"**
- Solution: Product/entitlement IDs must be full UUIDs. The scripts automatically fetch these for you.

**"unpermitted parameter"**
- Solution: Some API endpoints don't accept certain parameters. The scripts handle the correct API structure.

**"KEYGEN_API_TOKEN is not set"**  
- Solution: Check your `.env` file and ensure it's in the same directory as the scripts.

**Policy entitlements still showing on license despite choosing "none"**
- This is expected behavior - licenses automatically inherit policy entitlements. Remove via Keygen UI if needed.

### Getting Help

- **API Token Issues**: Check Keygen dashboard → Settings → Tokens
- **Account ID**: Check Keygen dashboard → Account Settings  
- **API Documentation**: Visit the Keygen API documentation
- **Script Issues**: Check script output for specific error messages

## Script Output

Both scripts provide:
- ✅ **Color-coded feedback** (green for success, red for errors, yellow for warnings)
- 📋 **Step-by-step progress** indicators
- 📝 **Detailed summaries** upon completion
- 🔍 **Clear error messages** with suggestions

### Example Success Output

```
══════════════════════════════════════
Policy Creation Complete!
══════════════════════════════════════
Name: ACME Corporation Service Contract Test Policy - BASIC, ADVANCED, PREMIUM
Customer Code: ACME001
Product ID: 12345678-1234-5678-9abc-def012345678
Entitlements: BASIC, ADVANCED, PREMIUM
Policy ID: 87654321-4321-8765-dcba-210fedcba987

Script completed successfully!
```

## Security Notes

- ⚠️ **Never commit your `.env` file** to version control
- 🔒 **Keep API tokens secure** and rotate them regularly  
- 👥 **Use least privilege** - only grant necessary permissions to tokens
- 🕒 **Tokens expire** - check token validity if scripts suddenly stop working