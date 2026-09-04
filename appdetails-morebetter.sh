#!/usr/bin/env bash

set -euo pipefail

APIGEE_LOGIN_URL="https://login.apigee.com/oauth/token"
APIGEE_MGMT_API_URL="https://api.enterprise.apigee.com/v1"
CLIENT_AUTH_HEADER="Basic ZWRnZWNsaTplZGdlY2xpc2VjcmV0"

echo "=== Apigee Edge App Extractor ==="

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
echo "Fetching app list from organization '$ORG_NAME'..."

# 2. Get all App IDs in the org
APPS_RESPONSE=$(curl -s -X GET "$APIGEE_MGMT_API_URL/organizations/$ORG_NAME/apps" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Accept: application/json")

APP_IDS=$(echo "$APPS_RESPONSE" | jq -r '.[]?')

if [ -z "$APP_IDS" ]; then
  echo "No apps found in organization '$ORG_NAME'."
  exit 0
fi

TOTAL_APPS=$(echo "$APP_IDS" | wc -l | tr -d ' ')
echo "Found $TOTAL_APPS total app(s) in org. Querying app details in parallel to filter for product '$PRODUCT_NAME'..."

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

export APIGEE_MGMT_API_URL ORG_NAME ACCESS_TOKEN PRODUCT_NAME TMP_DIR

# 3. Download full details for each app in parallel (-P 10) and save only those matching the product
echo "$APP_IDS" | xargs -I {} -P 10 bash -c '
  APP_ID="$1"
  APP_DETAIL=$(curl -s -X GET "$APIGEE_MGMT_API_URL/organizations/$ORG_NAME/apps/$APP_ID" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Accept: application/json")

  # Check if any credential in the app contains the target API product
  MATCH=$(echo "$APP_DETAIL" | jq --arg prod "$PRODUCT_NAME" -r '
    [ .credentials[]?.apiProducts[]?.apiproduct ] | contains([$prod])
  ')

  if [ "$MATCH" = "true" ]; then
    echo "$APP_DETAIL" > "$TMP_DIR/$APP_ID.json"
  fi
' _ {}

# 4. Combine all matching JSON files into a single array
MATCHING_APPS=$(jq -s '.' "$TMP_DIR"/*.json 2>/dev/null || echo "[]")

FETCHED_COUNT=$(echo "$MATCHING_APPS" | jq 'length')
echo -e "\nFound $FETCHED_COUNT app(s) associated with product '$PRODUCT_NAME':\n"

# Output formatted JSON to stdout
echo "$MATCHING_APPS" | jq '.'

# Save output to file
OUTPUT_FILE="${ORG_NAME}_${PRODUCT_NAME}_apps.json"
echo "$MATCHING_APPS" | jq '.' > "$OUTPUT_FILE"

echo -e "\nResults saved to '$OUTPUT_FILE'"
