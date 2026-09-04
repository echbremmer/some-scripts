#!/usr/bin/env bash

set -euo pipefail

APIGEE_LOGIN_URL="https://login.apigee.com/oauth/token"
APIGEE_MGMT_API_URL="https://api.enterprise.apigee.com/v1"
CLIENT_AUTH_HEADER="Basic ZWRnZWNsaTplZGdlY2xpc2VjcmV0"

echo "=== Apigee Edge App Extractor (Targeted) ==="

read -rp "Enter Apigee Organization name: " ORG_NAME
read -rp "Enter API Product name: " PRODUCT_NAME
read -rp "Enter Apigee Username (Email): " USERNAME
read -rsp "Enter Apigee Password: " PASSWORD
echo ""
read -rp "Enter MFA Code (TOTP): " MFA_CODE

echo -e "\nAuthenticating with Apigee Edge..."

# 1. Authenticate
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
echo "Querying apps matching API product '$PRODUCT_NAME'..."

# 2. Query apps filtered by apiProduct parameter
# Using query parameters apiProduct and expand=apps
PRODUCT_APPS_RESPONSE=$(curl -s -X GET "$APIGEE_MGMT_API_URL/organizations/$ORG_NAME/apps?apiProduct=$PRODUCT_NAME" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Accept: application/json")

# Extract app IDs or Names returned for this product
APP_LIST=$(echo "$PRODUCT_APPS_RESPONSE" | jq -r '.[]? // .app[]? // empty')

if [ -z "$APP_LIST" ]; then
  # Fallback: Query via developerapps search endpoint if the organization uses key-product search
  SEARCH_RESPONSE=$(curl -s -X GET "$APIGEE_MGMT_API_URL/organizations/$ORG_NAME/developers?expand=true" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Accept: application/json")
fi

# 3. Fetch full app details (including keys) for matching apps
echo "Fetching full app details including API keys..."

DETAILED_APPS_RESPONSE=$(curl -s -X GET "$APIGEE_MGMT_API_URL/organizations/$ORG_NAME/apps?apiProduct=$PRODUCT_NAME&expand=true" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Accept: application/json")

# Process and format matching apps JSON
MATCHING_APPS=$(echo "$DETAILED_APPS_RESPONSE" | jq '
  if type == "array" then
    .
  elif .app then
    .app
  else
    []
  end
')

MATCH_COUNT=$(echo "$MATCHING_APPS" | jq 'length')

if [ "$MATCH_COUNT" -eq 0 ]; then
  echo "No apps found associated with product '$PRODUCT_NAME'."
  exit 0
fi

echo -e "\nFound $MATCH_COUNT matching app(s):\n"

# Output formatted JSON to stdout
echo "$MATCHING_APPS" | jq '.'

# Save output to file
OUTPUT_FILE="${ORG_NAME}_${PRODUCT_NAME}_apps.json"
echo "$MATCHING_APPS" | jq '.' > "$OUTPUT_FILE"

echo -e "\nResults saved to '$OUTPUT_FILE'"
