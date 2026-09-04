#!/usr/bin/env bash

set -euo pipefail

APIGEE_LOGIN_URL="https://login.apigee.com/oauth/token"
APIGEE_MGMT_API_URL="https://api.enterprise.apigee.com/v1"
CLIENT_AUTH_HEADER="Basic ZWRnZWNliplZGdlY2xpc2VjcmV0"

echo "=== Apigee Edge App Extractor ==="

read -rp "Enter Apigee Organization name: " ORG_NAME
read -rp "Enter API Product name: " PRODUCT_NAME
read -rp "Enter Apigee Username (Email): " USERNAME
read -rsp "Enter Apigee Password: " PASSWORD
echo ""
read -rp "Enter MFA Code (TOTP): " MFA_CODE

echo -e "\nAuthenticating with Apigee Edge..."

# 1. Authenticate and extract OAuth Token
AUTH_RESPONSE=$(curl -s -X POST "$APIGEE_LOGIN_URL?mfa_token=$MFA_CODE" \
  -H "Authorization: $CLIENT_AUTH_HEADER" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -H "Accept: application/json" \
  --data-urlencode "grant_type=password" \
  --data-urlencode "username=$USERNAME" \
  --data-urlencode "password=$PASSWORD")

ACCESS_TOKEN=$(echo "$AUTH_RESPONSE" | jq -r '.access_token // empty')

if [ -z "$ACCESS_TOKEN" ]; then
  echo "Authentication failed!" >&2
  echo "Response: $AUTH_RESPONSE" >&2
  exit 1
fi

echo "Authentication successful."
echo "Fetching all apps with full details for org '$ORG_NAME'..."

# 2. Fetch all apps with expanded details in a single API call
APPS_RESPONSE=$(curl -s -X GET "$APIGEE_MGMT_API_URL/organizations/$ORG_NAME/apps?expand=true" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Accept: application/json")

# Verify we got a valid JSON response from Apigee
if ! echo "$APPS_RESPONSE" | jq -e '.' >/dev/null 2>&1; then
  echo "Error: Received non-JSON response from Apigee API." >&2
  echo "Response: $APPS_RESPONSE" >&2
  exit 1
fi

# 3. Filter the expanded app list using jq
MATCHING_APPS=$(echo "$APPS_RESPONSE" | jq --arg prod "$PRODUCT_NAME" '
  # Handle both object wrapper {.app: [...]} and raw array [...]
  (if type == "object" and .app then .app elif type == "array" then . else [] end)
  | map(
      select(
        .credentials[]?.apiProducts[]?.apiproduct == $prod
      )
    )
')

MATCH_COUNT=$(echo "$MATCHING_APPS" | jq 'length')

echo -e "\nFound $MATCH_COUNT matching app(s):\n"

# Output formatted JSON with full details (API keys included)
echo "$MATCHING_APPS" | jq '.'

# Save full details to output file
OUTPUT_FILE="${ORG_NAME}_${PRODUCT_NAME}_apps.json"
echo "$MATCHING_APPS" | jq '.' > "$OUTPUT_FILE"

echo -e "\nResults saved to '$OUTPUT_FILE'"
