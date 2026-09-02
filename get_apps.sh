#!/usr/bin/env bash

set -euo pipefail

APIGEE_LOGIN_URL="https://login.apigee.com/oauth/token"
APIGEE_MGMT_API_URL="https://api.enterprise.apigee.com/v1"

# Hardcoded Basic Auth header for Apigee Edge OAuth client (edgecli:edgeclisecret)
CLIENT_AUTH_HEADER="Basic ZWRnZWNsaTplZGdlY2xpc2VjcmV0"

echo "=== Apigee Edge App Extractor ==="

# Prompt for inputs
read -rp "Enter Apigee Organization name: " ORG_NAME
read -rp "Enter API Product name: " PRODUCT_NAME
read -rp "Enter Apigee Username (Email): " USERNAME
read -rsp "Enter Apigee Password: " PASSWORD
echo ""
read -rp "Enter MFA Code (TOTP): " MFA_CODE

echo -e "\nAuthenticating with Apigee Edge..."

# Fetch OAuth Token
AUTH_RESPONSE=$(curl -s -X POST "$APIGEE_LOGIN_URL?mfa_token=$MFA_CODE" \
  -H "Authorization: $CLIENT_AUTH_HEADER" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -H "Accept: application/json" \
  --data-urlencode "grant_type=password" \
  --data-urlencode "username=$USERNAME" \
  --data-urlencode "password=$PASSWORD")

# Extract access_token or handle error
ACCESS_TOKEN=$(echo "$AUTH_RESPONSE" | jq -r '.access_token // empty')

if [ -z "$ACCESS_TOKEN" ]; then
  echo "Authentication failed!" >&2
  echo "Response: $AUTH_RESPONSE" >&2
  exit 1
fi

echo "Authentication successful."
echo "Fetching apps containing product '$PRODUCT_NAME' in org '$ORG_NAME'..."

# Fetch all apps with expanded credentials and filter with jq
APPS_RESPONSE=$(curl -s -X GET "$APIGEE_MGMT_API_URL/organizations/$ORG_NAME/apps?expand=true" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Accept: application/json")

# Filter matching apps using jq
MATCHING_APPS=$(echo "$APPS_RESPONSE" | jq --arg prod "$PRODUCT_NAME" '
  [ .app[]? | select(
      .credentials[]?.apiProducts[]?.apiproduct == $prod
    )
  ]
')

MATCH_COUNT=$(echo "$MATCHING_APPS" | jq 'length')

echo -e "\nFound $MATCH_COUNT matching app(s):\n"

# Output formatted JSON to stdout
echo "$MATCHING_APPS" | jq '.'

# Save output to file
OUTPUT_FILE="${ORG_NAME}_${PRODUCT_NAME}_apps.json"
echo "$MATCHING_APPS" | jq '.' > "$OUTPUT_FILE"

echo -e "\nResults saved to '$OUTPUT_FILE'"
