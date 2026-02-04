# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Cross-platform CLI scripts for managing software licensing through the Keygen REST API. Provides both Bash and PowerShell implementations for creating policies (licensing rules) and licenses (individual license instances).

## Running Scripts

**Bash (Linux/macOS with Bash 4+):**
```bash
chmod +x create_policy.sh create_license.sh  # one-time setup
./create_policy.sh
./create_license.sh
```

**PowerShell (Windows/macOS/Linux):**
```powershell
.\Create-Policy.ps1
.\Create-License.ps1
pwsh ./Create-Policy.ps1    # macOS/Linux with PowerShell Core
```

Note: macOS ships with Bash 3.2. Scripts require Bash 4+ for associative arrays and will exit with an error if the version is too old. Install modern Bash via Homebrew or use PowerShell.

## Architecture

### Two-Script Pattern
- **Policy scripts** (`create_policy.sh` / `Create-Policy.ps1`): Create licensing policies that define rules and constraints
- **License scripts** (`create_license.sh` / `Create-License.ps1`): Create individual licenses under existing policies

Both scripts follow the same flow: Load `.env` → Fetch data from API → Interactive user selection → POST creation request → Display results

### Key Implementation Patterns

**Environment Management:**
- Configuration via `.env` file (see `.env.example`)
- Custom parser handles quoted values, comments, and values containing `=`
- Required: `KEYGEN_API_URL`, `KEYGEN_ACCOUNT_ID`, `KEYGEN_API_TOKEN`

**API Communication:**
- Uses Keygen's JSON:API specification
- Endpoint pattern: `/v1/accounts/{account_id}/{resource}`
- Authentication: Bearer token in `Authorization` header
- Content-Type: `application/vnd.api+json`
- Automatic retry (3 attempts, 2-second backoff) on 5xx errors only

**JSON Processing:**
- Bash uses Python 3 subprocess for reliable JSON parsing (avoids shell quoting issues)
- PowerShell uses native `ConvertTo-Json` and `Invoke-RestMethod`
- Metadata passed as null-separated pairs to prevent shell injection

**Pagination:**
- Keygen API returns max 100 items per page
- Scripts automatically fetch and merge all pages

**User Interaction:**
- Color-coded output: green (success), red (errors), yellow (prompts), cyan (info)
- Step-by-step numbered guidance
- Auto-selection when only one option available
- Multi-select support via space-separated numbers
- Confirmation prompt before creating resources (`[y/N]`)

## Dependencies

**Bash scripts:** curl, python3, standard Unix tools (sed, grep, mapfile)
**PowerShell scripts:** None beyond PowerShell standard library

No package managers, build tools, or external dependencies.

## Dual Implementation Requirement

When modifying functionality, maintain feature parity between Bash and PowerShell versions. Both implementations should:
- Have identical user-facing behavior
- Use the same API payloads
- Produce the same output format
- Handle the same edge cases
