#!/bin/bash

# Replace these variables with your actual values
ORG_NAME="your_organization_name"
ENV_NAME="your_environment_name"

# File to store OAuth token and refresh token
TOKEN_FILE="apigee_token.json"

# Function to get a new OAuth token
get_oauth_token() {
    read -s -p "Enter username: " USERNAME
    read -s -p "Enter password: " PASSWORD
    read -s -p "Enter MFA code: " APIGEE_API_KEY

    TOKEN_RESPONSE=$(curl -s https://api.enterprise.apigee.com/v1/organizations/$ORG_NAME/accessTokens \
        -d "grant_type=password&username=$USERNAME&password=$PASSWORD" \
        -H "Authorization: Basic $(echo -n 'your_client_id:$APIGEE_API_KEY' | base64)")
    
    if [ "$?" != 0 ]; then
        echo "Failed to get OAuth token. Please check your credentials."
        exit 1
    fi

    ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
    REFRESH_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.refresh_token')

    # Save the tokens to a file
    echo "{\"access_token\": \"$ACCESS_TOKEN\", \"refresh_token\": \"$REFRESH_TOKEN\"}" > $TOKEN_FILE
    echo "OAuth token saved."
}

# Function to load OAuth token from cache
load_oauth_token() {
    if [ ! -f "$TOKEN_FILE" ]; then
        get_oauth_token
    fi

    # Load the tokens from the file
    ACCESS_TOKEN=$(jq -r '.access_token' $TOKEN_FILE)
    REFRESH_TOKEN=$(jq -r '.refresh_token' $TOKEN_FILE)

    echo "Loaded OAuth token."
}

# Function to refresh the OAuth token if it has expired
refresh_oauth_token() {
    read -s -p "Enter MFA code: " APIGEE_API_KEY

    TOKEN_RESPONSE=$(curl -s https://api.enterprise.apigee.com/v1/organizations/$ORG_NAME/accessTokens \
        -d "grant_type=refresh_token&refresh_token=$REFRESH_TOKEN" \
        -H "Authorization: Basic $(echo -n 'your_client_id:$APIGEE_API_KEY' | base64)")
    
    if [ "$?" != 0 ]; then
        echo "Failed to refresh OAuth token. Please check your credentials."
        exit 1
    fi

    ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
    REFRESH_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.refresh_token')

    # Update the tokens in the file
    jq --arg at "$ACCESS_TOKEN" --arg rt "$REFRESH_TOKEN" '.access_token = $at | .refresh_token = $rt' $TOKEN_FILE > temp.json && mv temp.json $TOKEN_FILE

    echo "OAuth token refreshed."
}

# Function to check if the OAuth token is expired
is_token_expired() {
    EXPIRES_AT=$(jq -r '.expires_in' < $TOKEN_FILE)
    CURRENT_TIME=$(date +%s)

    if [ "$CURRENT_TIME" -ge "$EXPIRES_AT" ]; then
        return 0 # Token has expired
    else
        return 1 # Token is still valid
    fi
}

# Function to print table header
print_header() {
    echo "Proxy Name\tBase Path\tRevision"
    echo "----------\t---------\t--------"
}

# Main script logic
load_oauth_token

if is_token_expired; then
    refresh_oauth_token
fi

# Get the list of all proxies in the specified environment
PROXIES=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
    "https://api.enterprise.apigee.com/v1/o/$ORG_NAME/environments/$ENV_NAME/apis")

if [ "$?" != 0 ]; then
    echo "Failed to get proxies. Please check your token."
    exit 1
fi

# Extract the base paths and revision numbers for each proxy
print_header
for PROXY in $(echo "$PROXIES" | jq -r '.apis[] | .name'); do
    BASE_PATH=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
        "https://api.enterprise.apigee.com/v1/o/$ORG_NAME/environments/$ENV_NAME/apis/$PROXY/proxyEndpoints/default" \
        | jq -r '.proxy.path')
    
    REV_NUMBER=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
        "https://api.enterprise.apigee.com/v1/o/$ORG_NAME/environments/$ENV_NAME/apis/$PROXY/revisions" \
        | jq -r '[.[] | select(.status == "deployed")] | .[0].revision')
    
    echo "$PROXY\t$BASE_PATH\t$REV_NUMBER"
done
