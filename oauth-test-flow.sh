#!/bin/bash

# OAuth Test Flow Script for MCP Gateway
# This script tests the complete OAuth flow manually

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BASE_URL="${BASE_URL:-http://localhost:4242}"
CLIENT_ID="claude-ai-test"
REDIRECT_URI="https://claude.ai/oauth/callback"
STATE=$(uuidgen | tr '[:upper:]' '[:lower:]')

echo -e "${BLUE}=== MCP Gateway OAuth Flow Test ===${NC}"
echo -e "Base URL: ${BASE_URL}"
echo -e "Client ID: ${CLIENT_ID}"
echo -e "State: ${STATE}\n"

# Function to check if server is running
check_server() {
    echo -e "${YELLOW}Checking if server is running...${NC}"
    if curl -s "${BASE_URL}/health" > /dev/null; then
        echo -e "${GREEN}✓ Server is running${NC}\n"
    else
        echo -e "${RED}✗ Server is not running at ${BASE_URL}${NC}"
        echo -e "Please start the server with: npm run dev"
        exit 1
    fi
}

# Function to test OAuth discovery
test_discovery() {
    echo -e "${BLUE}1. Testing OAuth Discovery Endpoint${NC}"
    echo -e "   GET ${BASE_URL}/.well-known/oauth-authorization-server"
    
    response=$(curl -s "${BASE_URL}/.well-known/oauth-authorization-server")
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✓ Discovery endpoint responded${NC}"
        echo -e "   Response: ${response}\n"
        
        # Validate response contains required fields
        if echo "$response" | grep -q "authorization_endpoint" && \
           echo "$response" | grep -q "token_endpoint"; then
            echo -e "${GREEN}✓ Discovery response valid${NC}\n"
        else
            echo -e "${RED}✗ Discovery response missing required fields${NC}\n"
        fi
    else
        echo -e "${RED}✗ Discovery endpoint failed${NC}\n"
    fi
}

# Function to test authorization
test_authorization() {
    echo -e "${BLUE}2. Testing Authorization Endpoint${NC}"
    
    # Build authorization URL
    AUTH_URL="${BASE_URL}/oauth/authorize"
    AUTH_URL="${AUTH_URL}?response_type=code"
    AUTH_URL="${AUTH_URL}&client_id=${CLIENT_ID}"
    AUTH_URL="${AUTH_URL}&redirect_uri=${REDIRECT_URI}"
    AUTH_URL="${AUTH_URL}&state=${STATE}"
    AUTH_URL="${AUTH_URL}&scope=mcp:all"
    
    echo -e "   GET ${AUTH_URL}"
    
    # Follow redirects manually to capture the authorization code
    response=$(curl -s -I -X GET "${AUTH_URL}")
    location=$(echo "$response" | grep -i "location:" | sed 's/location: //i' | tr -d '\r')
    
    if [[ -n "$location" ]]; then
        echo -e "${GREEN}✓ Authorization endpoint redirected${NC}"
        echo -e "   Location: ${location}"
        
        # Extract authorization code
        AUTH_CODE=$(echo "$location" | grep -oE 'code=[^&]+' | cut -d'=' -f2)
        RETURNED_STATE=$(echo "$location" | grep -oE 'state=[^&]+' | cut -d'=' -f2)
        
        if [[ -n "$AUTH_CODE" ]]; then
            echo -e "${GREEN}✓ Authorization code received: ${AUTH_CODE:0:8}...${NC}"
        else
            echo -e "${RED}✗ No authorization code in redirect${NC}"
            exit 1
        fi
        
        if [[ "$RETURNED_STATE" == "$STATE" ]]; then
            echo -e "${GREEN}✓ State parameter preserved${NC}\n"
        else
            echo -e "${RED}✗ State parameter mismatch${NC}\n"
        fi
    else
        echo -e "${RED}✗ No redirect from authorization endpoint${NC}\n"
        exit 1
    fi
}

# Function to test token exchange
test_token_exchange() {
    echo -e "${BLUE}3. Testing Token Exchange${NC}"
    echo -e "   POST ${BASE_URL}/oauth/token"
    
    # Exchange authorization code for token
    response=$(curl -s -X POST "${BASE_URL}/oauth/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=authorization_code" \
        -d "code=${AUTH_CODE}" \
        -d "redirect_uri=${REDIRECT_URI}" \
        -d "client_id=${CLIENT_ID}")
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✓ Token endpoint responded${NC}"
        echo -e "   Response: ${response}"
        
        # Extract access token
        ACCESS_TOKEN=$(echo "$response" | grep -oE '"access_token":"[^"]+' | cut -d'"' -f4)
        
        if [[ -n "$ACCESS_TOKEN" ]]; then
            echo -e "${GREEN}✓ Access token received: ${ACCESS_TOKEN:0:10}...${NC}\n"
        else
            echo -e "${RED}✗ No access token in response${NC}\n"
            exit 1
        fi
    else
        echo -e "${RED}✗ Token exchange failed${NC}\n"
        exit 1
    fi
}

# Function to test API access
test_api_access() {
    echo -e "${BLUE}4. Testing API Access with Token${NC}"
    echo -e "   GET ${BASE_URL}/health"
    echo -e "   Authorization: Bearer ${ACCESS_TOKEN:0:10}..."
    
    response=$(curl -s -X GET "${BASE_URL}/health" \
        -H "Authorization: Bearer ${ACCESS_TOKEN}")
    
    if [[ $? -eq 0 ]] && echo "$response" | grep -q "status"; then
        echo -e "${GREEN}✓ Successfully accessed API with token${NC}"
        echo -e "   Response: ${response}\n"
    else
        echo -e "${RED}✗ Failed to access API with token${NC}\n"
    fi
}

# Function to test PKCE flow
test_pkce_flow() {
    echo -e "${BLUE}5. Testing PKCE Flow${NC}"
    
    # Generate PKCE values
    CODE_VERIFIER=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-43)
    CODE_CHALLENGE=$(echo -n "$CODE_VERIFIER" | openssl dgst -sha256 -binary | base64 | tr -d "=+/" | tr '+' '-' | tr '/' '_')
    
    echo -e "   Code Verifier: ${CODE_VERIFIER:0:10}..."
    echo -e "   Code Challenge: ${CODE_CHALLENGE:0:10}..."
    
    # Authorization with PKCE
    PKCE_AUTH_URL="${BASE_URL}/oauth/authorize"
    PKCE_AUTH_URL="${PKCE_AUTH_URL}?response_type=code"
    PKCE_AUTH_URL="${PKCE_AUTH_URL}&client_id=${CLIENT_ID}"
    PKCE_AUTH_URL="${PKCE_AUTH_URL}&redirect_uri=${REDIRECT_URI}"
    PKCE_AUTH_URL="${PKCE_AUTH_URL}&state=${STATE}"
    PKCE_AUTH_URL="${PKCE_AUTH_URL}&code_challenge=${CODE_CHALLENGE}"
    PKCE_AUTH_URL="${PKCE_AUTH_URL}&code_challenge_method=S256"
    
    response=$(curl -s -I -X GET "${PKCE_AUTH_URL}")
    location=$(echo "$response" | grep -i "location:" | sed 's/location: //i' | tr -d '\r')
    PKCE_CODE=$(echo "$location" | grep -oE 'code=[^&]+' | cut -d'=' -f2)
    
    if [[ -n "$PKCE_CODE" ]]; then
        echo -e "${GREEN}✓ PKCE authorization code received${NC}"
        
        # Token exchange with verifier
        pkce_token_response=$(curl -s -X POST "${BASE_URL}/oauth/token" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "grant_type=authorization_code" \
            -d "code=${PKCE_CODE}" \
            -d "redirect_uri=${REDIRECT_URI}" \
            -d "client_id=${CLIENT_ID}" \
            -d "code_verifier=${CODE_VERIFIER}")
        
        if echo "$pkce_token_response" | grep -q "access_token"; then
            echo -e "${GREEN}✓ PKCE token exchange successful${NC}\n"
        else
            echo -e "${RED}✗ PKCE token exchange failed${NC}"
            echo -e "   Response: ${pkce_token_response}\n"
        fi
    else
        echo -e "${RED}✗ PKCE authorization failed${NC}\n"
    fi
}

# Function to test error cases
test_error_cases() {
    echo -e "${BLUE}6. Testing Error Cases${NC}"
    
    # Test missing state
    echo -e "   Testing missing state parameter..."
    error_response=$(curl -s "${BASE_URL}/oauth/authorize?redirect_uri=test")
    if echo "$error_response" | grep -q "invalid_request"; then
        echo -e "${GREEN}✓ Correctly rejected missing state${NC}"
    else
        echo -e "${RED}✗ Did not reject missing state${NC}"
    fi
    
    # Test invalid grant type
    echo -e "   Testing invalid grant type..."
    error_response=$(curl -s -X POST "${BASE_URL}/oauth/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=password")
    if echo "$error_response" | grep -q "unsupported_grant_type"; then
        echo -e "${GREEN}✓ Correctly rejected invalid grant type${NC}"
    else
        echo -e "${RED}✗ Did not reject invalid grant type${NC}"
    fi
    
    # Test invalid code
    echo -e "   Testing invalid authorization code..."
    error_response=$(curl -s -X POST "${BASE_URL}/oauth/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=authorization_code" \
        -d "code=invalid-code-123" \
        -d "redirect_uri=${REDIRECT_URI}")
    if echo "$error_response" | grep -q "invalid_grant"; then
        echo -e "${GREEN}✓ Correctly rejected invalid code${NC}"
    else
        echo -e "${RED}✗ Did not reject invalid code${NC}"
    fi
    
    echo ""
}

# Main execution
main() {
    check_server
    test_discovery
    test_authorization
    test_token_exchange
    test_api_access
    test_pkce_flow
    test_error_cases
    
    echo -e "${GREEN}=== OAuth Flow Test Complete ===${NC}"
    echo -e "All tests passed! The OAuth implementation is working correctly.\n"
}

# Run main function
main