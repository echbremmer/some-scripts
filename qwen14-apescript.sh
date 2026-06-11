#!/bin/bash

# Configuration
ORG_NAME="your_org_name"
ENVIRONMENT="your_environment"
APIGEE_USER="your_apigee_user_email"

# Function to get the MFA code (you need to implement this part)
get_mfa_code() {
  # You can use a tool like oathtool or google-authenticator-cli to generate the TOTP
  # For example:
  # oathtool --totp='YOUR_SECRET_KEY'
  echo "Enter your MFA code:"
  read -r mfa_code
  echo "$mfa_code"
}

# Get an access token (this is a simplified example, consider using a library for OAuth2)
get_access_token() {
  local username="$1"
  local password="$2"
  local mfa_code="$3"

  curl -s -X POST "https://login.apigee.com/oauth/token" \
    -d "grant_type=password" \
    -d "username=$username" \
    -d "password=$password" \
    -d "mfa-otp=$mfa_code" \
    -d "client_id=apigeecli" \
    -d "client_secret=your_edgecli_client_secret"
}

# Get the proxies and extract basepaths
get_proxies_basepaths() {
  local access_token="$1"

  # Fetch the list of proxies
  curl -s -H "Authorization: Bearer $access_token" \
       "https://api.enterprise.apigee.com/v1/organizations/$ORG_NAME/environments/$ENVIRONMENT/apis" | jq -r '.[].proxyName' |
  while read -r proxy_name; do
    # Get the basepath for each proxy
    curl -s -H "Authorization: Bearer $access_token" \
         "https://api.enterprise.apigee.com/v1/organizations/$ORG_NAME/apis/$proxy_name/revisions/latest/proxies/default" | jq -r '.BasePaths[0]'
  done
}

# Main execution flow
if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <password> <client_secret>"
  exit 1
fi

PASSWORD="$1"
CLIENT_SECRET="$2"

MFA_CODE=$(get_mfa_code)
ACCESS_TOKEN=$(get_access_token "$APIGEE_USER" "$PASSWORD" "$MFA_CODE")

if [[ -z "$ACCESS_TOKEN" ]]; then
  echo "Failed to obtain access token."
  exit 1
fi

echo "Access Token: $ACCESS_TOKEN"

# Extract and display basepaths of all proxies in the given environment
get_proxies_basepaths "$ACCESS_TOKEN"
