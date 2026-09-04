#!/usr/bin/env bash

set -euo pipefail

APIGEE_LOGIN_URL="https://login.apigee.com/oauth/token"
APIGEE_MGMT_API_URL="https://api.enterprise.apigee.com/v1"
CLIENT_AUTH_HEADER="Basic ZWRnZWNsaTplZGdlY2xpc2VjcmV0"

echo "=== Apigee Edge App Extractor (Targeted Fetch) ==="

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
echo "Fetching app list associated with product '$PRODUCT_NAME'..."

# 2. Get API Product details to extract only linked app names
PRODUCT_RESPONSE=$(curl -s -X GET "$APIGEE_MGMT_API_URL/organizations/$ORG_NAME/apiproducts/$PRODUCT_NAME" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Accept: application/json")

# Extract app names (handles both object/string list variations returned by Apigee API)
APP_NAMES=$(echo "$PRODUCT_RESPONSE" | jq -r '.hostedApps[]? // .app[]? // empty')

if [ -z "$APP_NAMES" ]; then
  echo "No apps found associated with product '$PRODUCT_NAME'."
  exit 0
fi

# Count total apps to fetch
TOTAL_APPS=$(echo "$APP_NAMES" | wc -l | tr -d ' ')
echo "Found $TOTAL_APPS app(s) linked to product '$PRODUCT_NAME'. Fetching detailed app records..."

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# 3. Fetch details concurrently only for the target apps
export APIGEE_MGMT_API_URL ORG_NAME ACCESS_TOKEN TMP_DIR

echo "$APP_NAMES" | xargs -I {} -P 10 bash -c '
  APP_NAME="$1"
  ENCODED_APP=$(printf %s "$APP_NAME" | jq -sRr @uri)
  RESPONSE=$(curl -s -X GET "$APIGEE_MGMT_API_URL/organizations/$ORG_NAME/apps/$ENCODED_APP" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Accept: application/json")
  
  if echo "$RESPONSE" | jq -e ".name" >/dev/null 2>&1; then
    echo "$RESPONSE" > "$TMP_DIR/$ENCODED_APP.json"
  fi
' _ {}

# 4. Combine all individual fetched app JSONs into a single output array
MATCHING_APPS=$(jq -s '.' "$TMP_DIR"/*.json 2>/dev/null || echo "[]")

FETCHED_COUNT=$(echo "$MATCHING_APPS" | jq 'length')
echo -e "\nSuccessfully retrieved details for $FETCHED_COUNT matching app(s):\n"

# Print output to stdout
echo "$MATCHING_APPS" | jq '.'

# Save output to file
OUTPUT_FILE="${ORG_NAME}_${PRODUCT_NAME}_apps.json"
echo "$MATCHING_APPS" | jq '.' > "$OUTPUT_FILE"

echo -e "\nResults saved to '$OUTPUT_FILE'"
