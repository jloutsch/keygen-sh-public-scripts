# Environment Configuration Guide

This guide explains how to set up your environment file for the Keygen API scripts.

## Quick Start

1. **Copy the example file:**
   ```bash
   cp .env.example .env
   ```

2. **Edit the .env file** with your actual values

3. **Test your configuration:**
   ```bash
   # For Bash
   ./create_policy_v2.sh
   
   # For PowerShell
   .\Create-Policy.ps1
   ```

## Configuration Values

### 🔗 KEYGEN_API_URL

**What it is:** The base URL for the Keygen API

**Where to find it:**
- **Keygen Cloud:** Always use `https://api.keygen.sh`
- **Self-hosted:** Use your custom domain

**Example values:**
```
# Keygen Cloud
KEYGEN_API_URL=https://api.keygen.sh

# Self-hosted
KEYGEN_API_URL=https://licensing.yourcompany.com
```

### 🆔 KEYGEN_ACCOUNT_ID

**What it is:** Your unique account identifier in UUID format

**Where to find it:**
1. Log into your Keygen dashboard
2. Navigate to **Settings** → **Account**
3. Copy the **Account ID** (UUID format)

**Example value:**
```
KEYGEN_ACCOUNT_ID=your-account-id-uuid-here
```

**Important:**
- Must be in lowercase
- Must be a valid UUID format
- Unique to your account

### 🔑 KEYGEN_API_TOKEN

**What it is:** Authentication token for API access

**How to generate:**
1. Log into your Keygen dashboard
2. Navigate to **Settings** → **Tokens**
3. Click **"New Token"**
4. Configure token permissions:
   - **Name:** Give it a descriptive name (e.g., "Script Token")
   - **Permissions:** Select appropriate permissions
   - **Expiry:** Set an expiration date (recommended for security)
5. Click **"Create Token"**
6. **Copy the token immediately** (you won't see it again!)

**Required Permissions:**

For **Policy Creation**:
- `policies:create` - Create new policies
- `products:read` - List products
- `entitlements:read` - List entitlements
- `policies:attach` - Attach entitlements to policies

For **License Creation**:
- `licenses:create` - Create new licenses
- `policies:read` - List and search policies

**Example values:**
```
# Production token
KEYGEN_API_TOKEN=prod-ABc123XyZ789DefGHI456jkLMNopQRS

# Test token
KEYGEN_API_TOKEN=test-XyZ789ABc123DefGHI456jkLMNopQRS

# Legacy format (example only - not a real token)
KEYGEN_API_TOKEN=keygen-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

## Complete Example Files

### Basic Configuration (.env)
```bash
# Keygen API Configuration
KEYGEN_API_URL=https://api.keygen.sh
KEYGEN_ACCOUNT_ID=your-account-id-uuid-here
KEYGEN_API_TOKEN=prod-ABc123XyZ789DefGHI456jkLMNopQRS
```

### Advanced Configuration (.env)
```bash
# Keygen API Configuration
KEYGEN_API_URL=https://api.keygen.sh
KEYGEN_ACCOUNT_ID=your-account-id-uuid-here
KEYGEN_API_TOKEN=prod-ABc123XyZ789DefGHI456jkLMNopQRS

# Optional: Default values for scripts
DEFAULT_PRODUCT_ID=your-product-id-uuid-here
DEFAULT_CUSTOMER_PREFIX=ACME
DEBUG_MODE=false

# Optional: Environment-specific settings
ENVIRONMENT=production
LOG_LEVEL=info
```

## Security Best Practices

### ✅ DO:
- **Use environment-specific tokens** (dev, staging, production)
- **Set token expiration dates** when creating tokens
- **Store production credentials in a password manager**
- **Use read-only permissions** when write access isn't needed
- **Rotate tokens regularly** (every 90 days recommended)
- **Add `.env` to `.gitignore`** to prevent accidental commits

### ❌ DON'T:
- **Never commit `.env` files** to version control
- **Never share tokens** in emails, Slack, or other communications
- **Never use production tokens** in development environments
- **Never embed tokens** directly in scripts
- **Never use admin tokens** for automated scripts

## Testing Your Configuration

### Test Connection (Bash)
```bash
# Quick test to verify your credentials
curl -H "Authorization: Bearer ${KEYGEN_API_TOKEN}" \
     -H "Accept: application/vnd.api+json" \
     "${KEYGEN_API_URL}/v1/accounts/${KEYGEN_ACCOUNT_ID}/products"
```

### Test Connection (PowerShell)
```powershell
# Quick test to verify your credentials
$headers = @{
    "Authorization" = "Bearer $env:KEYGEN_API_TOKEN"
    "Accept" = "application/vnd.api+json"
}
Invoke-RestMethod -Uri "$env:KEYGEN_API_URL/v1/accounts/$env:KEYGEN_ACCOUNT_ID/products" -Headers $headers
```

## Troubleshooting

### "401 Unauthorized"
- **Cause:** Invalid or expired token
- **Solution:** Generate a new token in the Keygen dashboard

### "404 Not Found"
- **Cause:** Incorrect account ID or API URL
- **Solution:** Verify your account ID and API URL

### "403 Forbidden"
- **Cause:** Token lacks required permissions
- **Solution:** Create a new token with appropriate permissions

### Environment Variables Not Loading
- **Bash:** Ensure `.env` is in the same directory as the script
- **PowerShell:** Check that the script is reading the `.env` file correctly
- **Both:** Verify no extra spaces around `=` in the `.env` file

## Distribution Guide

When sharing these scripts with team members:

1. **Share the `.env.example` file** (safe to commit to version control)
2. **Never share your actual `.env` file**
3. **Each team member should:**
   - Copy `.env.example` to `.env`
   - Get their own API token from the Keygen dashboard
   - Fill in their credentials
4. **For production use:**
   - Consider using a secrets management system
   - Use environment variables set by your CI/CD pipeline
   - Implement token rotation policies

## Support

If you're having trouble finding your configuration values:
1. Check the [Keygen Documentation](https://keygen.sh/docs)
2. Contact your Keygen account administrator
3. Reach out to Keygen support if you have an active subscription