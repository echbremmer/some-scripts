#!/bin/bash

# Configuration
ORG_NAME="your_org_name"
ENVIRONMENT="your_environment"
APIGEE_USER="your_apigee_user_email"

# Function to get the MFA code interactively
get_mfa_code() {
  read -r -s -p "Enter your MFA code: " mfa_code
  echo # Move to the next line after input
  echo "$mfa_code"
}

# Function to get the password interactively
get_password() {
  read -r -s -p "Enter your Apigee Password: " password
  echo # Move to the next line after input
  echo "$password"
}

# Ensure client_id and client_secret are set in environment variables
if [[ -z "$APGEE_CLIENT_ID" || -z "$APGEE_CLIENT_SECRET" ]]; then
  echo "Error: APGEE_CLIENT_ID or APGEE_CLIENT_SECRET is not set."
  exit 1
fi

# Get password and MFA code from user
PASSWORD=$(get_password)
MFA_CODE=$(get_mfa_code)

# Send the POST request to obtain an access token using -d option
response=$(curl -s \
    --request POST \
    --url https://login.apigee.com/oauth/token \
    --header "Authorization: Basic $(echo -n "$APGEE_CLIENT_ID:$APGEE_CLIENT_SECRET" | base64)" \
    --data-urlencode "grant_type=password" \
    --data-urlencode "username=$APIGEE_USER" \
    --data-urlencode "password=$PASSWORD" \
    --data-urlencode "mfa_code=$MFA_CODE")

# Extract the access token from the response
access_token=$(echo "$response" | jq -r '.access_token')

if [[ -z "$access_token" || "$access_token" == "null" ]]; then
  echo "Error: Failed to obtain access token. Please check your credentials and try again."
  exit 1
fi

# Use the obtained access token to fetch proxies in the specified environment
proxies_response=$(curl -s \
    --request GET \
    --url "https://api.enterprise.apigee.com/v1/organizations/$ORG_NAME/environments/$ENVIRONMENT/apis" \
    --header "Authorization: Bearer $access_token")

# Check if there was an error fetching proxies
if [[ $(echo "$proxies_response" | jq -e '.error' 2>/dev/null) ]]; then
  echo "Error: Failed to fetch proxies. Please check your access token and try again."
  exit 1
fi

# Pretty-print the list of proxies using jq
echo "$proxies_response" | jq '.'
