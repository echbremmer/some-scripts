#!/usr/bin/env bash

set -euo pipefail

APIGEE_LOGIN_URL="https://login.apigee.com/oauth/token"
APIGEE_MGMT_API_URL="https://api.enterprise.apigee.com/v1"

# Basic Auth header for Apigee Edge OAuth client (edgecli:edgeclisecret)
CLIENT_AUTH_HEADER="Basic ZWRnZWNsaTplZGdlY2xpc2VjcmV0"

echo "=== Apigee Edge App Details Extractor (FromFile) ==="

# Prompt for inputs
read -rp "Enter path to JSON input file [e.g., apps.json]: " INPUT_FILE
read -rp "Enter Apigee Organization name: " ORG_NAME
read -rp "Enter Apigee Username (Email): " USERNAME
read -rsp "Enter Apigee Password: " PASSWORD
echo ""
read -rp "Enter MFA Code (TOTP): " MFA_CODE

# Validate input file existence and JSON format
if [ ! -f "$INPUT_FILE" ]; then
  echo "Error: File '$INPUT_FILE' not found." >&2
  exit 1
fi

if ! jq -e 'type == "array"' "$INPUT_FILE" >/dev/null 2>&1; then
  echo "Error: File '$INPUT_FILE' must contain a valid JSON array of strings, e.g., [\"app1\", \"app2\"]." >&2
  exit 1
fi

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

# Extract app IDs from the input JSON array
APP_IDS=$(jq -r '.[]' "$INPUT_FILE")
TOTAL_APPS=$(echo "$APP_IDS" | grep -c . || true)

if [ "$TOTAL_APPS" -eq 0 ]; then
  echo "No app IDs found in '$INPUT_FILE'."
  exit 0
fi

echo "Found $TOTAL_APPS app ID(s) in '$INPUT_FILE'. Fetching details..."

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

export APIGEE_MGMT_API_URL ORG_NAME ACCESS_TOKEN TMP_DIR

# 2. Fetch each app detail in parallel using xargs
echo "$APP_IDS" | xargs -I {} -P 10 bash -c '
  APP_ID="$1"
  # URL encode the app ID in case it contains spaces or special characters
  ENCODED_APP=$(printf %s "$APP_ID" | jq -sRr @uri)
  
  RESPONSE=$(curl -s -X GET "$APIGEE_MGMT_API_URL/organizations/$ORG_NAME/apps/$ENCODED_APP" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Accept: application/json")

  if echo "$RESPONSE" | jq -e ".name or .appId" >/dev/null 2>&1; then
    echo "$RESPONSE" > "$TMP_DIR/app_$(echo -n "$APP_ID" | sha256sum | awk "{print \$1}").json"
  else
    echo "Warning: Could not retrieve app details for ID/Name: $APP_ID" >&2
  fi
' _ {}

# 3. Combine retrieved app JSONs into a single array
APP_DETAILS=$(jq -s '.' "$TMP_DIR"/*.json 2>/dev/null || echo "[]")
RETRIEVED_COUNT=$(echo "$APP_DETAILS" | jq 'length')

echo -e "\nSuccessfully retrieved details for $RETRIEVED_COUNT of $TOTAL_APPS app(s):\n"

# Output formatted JSON with full details to stdout
echo "$APP_DETAILS" | jq '.'

# Save full details to output file
OUTPUT_FILE="${ORG_NAME}_app_details.json"
echo "$APP_DETAILS" | jq '.' > "$OUTPUT_FILE"

echo -e "\nResults saved to '$OUTPUT_FILE'"
