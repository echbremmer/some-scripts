#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status,
# or if an uninitialized variable is used.
set -euo pipefail

# Configuration
MGMT_API="https://api.enterprise.apigee.com/v1"
OUTPUT_DIR="./apigee_bundles"

echo "=== Apigee Edge Proxy Downloader (MFA Enabled) ==="

# 1. Gather Credentials safely
read -p "Enter your Apigee Org Name: " ORG
read -p "Enter your Apigee Environment Name: " ENV
read -p "Enter your Apigee Email Username: " USERNAME
read -s -p "Enter your Apigee Password: " PASSWORD
echo ""

echo "---------------------------------------------------"
echo "For MFA, you can either:"
echo "1) Enter your raw 6-digit current token right now."
echo "2) Enter your 16-character TOTP Secret Key (script will generate codes automatically via 'oathtool')."
echo "---------------------------------------------------"
read -p "Enter MFA Token OR TOTP Secret Key: " MFA_INPUT

# 2. Handle MFA Token Generation / Assignment
if [ ${#MFA_INPUT} -eq 6 ] && [[ "$MFA_INPUT" =~ ^[0-9]+$ ]]; then
    MFA_TOKEN="$MFA_INPUT"
else
    if ! command -v oathtool &> /dev/null; then
        echo "Error: 'oathtool' is required to parse TOTP secret keys. Install it or provide a 6-digit code."
        exit 1
    fi
    MFA_TOKEN=$(oathtool --totp -b "$MFA_INPUT")
    echo "Generated MFA Token: $MFA_TOKEN"
fi

# 3. Authenticate and obtain OAuth2 Access Token
echo "Authenticating with Apigee Edge..."

# Apigee's public OAuth token endpoint client ID and secret
CLIENT_ID="edgecli"
CLIENT_SECRET="edgeclisecret"

TOKEN_RESPONSE=$(curl -s -X POST "https://login.apigee.com/oauth/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -H "Accept: application/json;charset=utf-8" \
  -u "$CLIENT_ID:$CLIENT_SECRET" \
  -d "username=$USERNAME" \
  -d "password=$PASSWORD" \
  -d "grant_type=password" \
  -d "mfa_token=$MFA_TOKEN")

# Verify token success
if echo "$TOKEN_RESPONSE" | jq -e '.access_token' > /dev/null; then
    ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
    echo "Authentication successful!"
else
    echo "Authentication failed. Response details:"
    echo "$TOKEN_RESPONSE" | jq .
    exit 1
fi

# Create backup directory
mkdir -p "$OUTPUT_DIR"

# 4. Fetch all proxies deployed or existing in the Org
echo "Fetching list of proxies..."
PROXIES=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "$MGMT_API/organizations/$ORG/apis")

if [ "$(echo "$PROXIES" | jq '. | type')" != "array" ]; then
    echo "Failed to retrieve proxies or organization not found."
    echo "$PROXIES"
    exit 1
fi

PROXY_COUNT=$(echo "$PROXIES" | jq '. | length')
echo "Found $PROXY_COUNT proxies. Starting download..."

# 5. Loop through proxies and grab the latest revision
echo "$PROXIES" | jq -r '.[]' | while read -r PROXY_NAME; do
    echo "Processing proxy: $PROXY_NAME"
    
    # Get details to find the highest revision number
    PROXY_DETAILS=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "$MGMT_API/organizations/$ORG/apis/$PROXY_NAME")
    LATEST_REVISION=$(echo "$PROXY_DETAILS" | jq -r '.revision | map(tonumber) | max')
    
    if [ "$LATEST_REVISION" = "null" ] || [ -z "$LATEST_REVISION" ]; then
        echo "  [!] No revisions found for $PROXY_NAME. Skipping."
        continue
    fi
    
    TARGET_ZIP="$OUTPUT_DIR/${PROXY_NAME}_rev${LATEST_REVISION}.zip"
    echo "  -> Downloading revision $LATEST_REVISION to $TARGET_ZIP"
    
    # Download the bundle zip archive
    HTTP_STATUS=$(curl -s -w "%{http_code}" -o "$TARGET_ZIP" \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      "$MGMT_API/organizations/$ORG/apis/$PROXY_NAME/revisions/$LATEST_REVISION?format=bundle")
    
    if [ "$HTTP_STATUS" -ne 200 ]; then
        echo "  [!] Failed to download bundle for $PROXY_NAME (HTTP Status: $HTTP_STATUS)"
        rm -f "$TARGET_ZIP"
    fi
done

echo "=== Finished! All bundles are saved in $OUTPUT_DIR ==="
