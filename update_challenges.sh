#!/bin/bash

CHALLENGES_USER=${CHALLENGES_USER}
CHALLENGES_URL=${CHALLENGES_URL}
CHALLENGES_PASSWORD=${CHALLENGES_PASSWORD}

# Get the input response and ensure it's proper JSON
format_response() {
    local input="$1"
    # Check if the string starts with a curly brace
    if [[ ! "$input" == \{* ]]; then
        input="{$input"
    fi
    echo "$input"
}

RESPONSE=$(format_response "$1")
echo "Formatted response: $RESPONSE"



# Function to get JWT token for challenges
get_challenge_token() {
    echo "Getting JWT token for challenges..."
    echo "Using URL: ${CHALLENGES_URL}/rpc/login"
    echo "Using user: ${CHALLENGES_USER}"
    
    # Store the full response first
    TOKEN=$(curl -s -X POST "${CHALLENGES_URL}/rpc/login" \
        -H "Content-Type: application/json" \
        -d "{\"email\": \"${CHALLENGES_USER}\", \"pass\": \"${CHALLENGES_PASSWORD}\"}" \
        2>&1)
    
    echo "Full response from login attempt:"
    #echo "$TOKEN"
    
    # Extract the response body (everything after the response headers)
    TOKEN_BODY=$(echo "$TOKEN" | awk 'BEGIN{rs=""}/./{p=1}p')
    
    #echo "Response body:"
    #echo "$TOKEN_BODY"
    
    # Try to parse the token
    TOKEN=$(echo "$TOKEN_BODY" | jq -r '.token // empty')
    
    if [ -n "$TOKEN" ]; then
        echo "Successfully obtained JWT token"
        echo "Token starts with: ${TOKEN:0:20}..."
        return 0
    else
        echo "Failed to obtain JWT token"
        echo "jq parsing error code: $?"
        return 1
    fi
}


# Function to get user challenges
get_user_challenges() {
    echo "Fetching user challenges..."
    echo "Using URL: ${CHALLENGES_URL}/user_challenges"
    #echo "Using token starting with: ${TOKEN:0:20}..."
    
    CHALLENGES_RESPONSE=$(curl -s "${CHALLENGES_URL}/user_challenges" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        2>&1)
    
    echo "Full challenges response:"
    echo "$CHALLENGES_RESPONSE"
    
    # Try to parse the challenges
    CHALLENGES=$(echo "$CHALLENGES_RESPONSE" | awk 'BEGIN{rs=""}/./{p=1}p' | jq '.')
    
    if [ $? -eq 0 ]; then
        echo "Successfully parsed challenges"
        echo "Retrieved challenges: $CHALLENGES"
    else
        echo "Failed to parse challenges response"
        echo "Raw response body:"
        echo "$CHALLENGES_RESPONSE" | awk 'BEGIN{rs=""}/./{p=1}p'
    fi
}

# Function to check if a date falls within a challenge period
is_date_in_range() {
    local track_date="$1"
    local challenge_from="$2"
    local challenge_to="$3"

    # Convert track date from "DD MMM YYYY - HH:MM:SS CET" to YYYY-MM-DD
    track_date_converted=$(date -d "$(echo $track_date | cut -d'-' -f1)" +%Y-%m-%d)
    
    # Compare dates using proper string comparison
    if [[ "$track_date_converted" > "$challenge_from" || "$track_date_converted" == "$challenge_from" ]] && \
       [[ "$track_date_converted" < "$challenge_to" || "$track_date_converted" == "$challenge_to" ]]; then
        return 0
    else
        return 1
    fi
}

# Function to convert activity type
normalize_activity_type() {
    local activity="$1"
    case "${activity,,}" in
        "biking"|"cycling") echo "cycling" ;;
        "running"|"run") echo "running" ;;
        *) echo "$activity" ;;
    esac
}

# Function to process upload response and submit to matching challenges
process_upload() {
    local RESPONSE="$1"
    local CHALLENGES_RESPONSE="$2"
    local TOKEN="$3"

    echo "Upload response being used:"
    echo "$RESPONSE"
    # First verify that we have valid JSON input
    if ! echo "$RESPONSE" | jq empty 2>/dev/null; then
        echo "Error: Invalid JSON response"
        return 1
    fi

    # Parse upload response with null checks
    local track_date=$(echo "$RESPONSE" | jq -r '.date')
    local activity_type=$(echo "$RESPONSE" | jq -r '.activitytype')
    local distance=$(echo "$RESPONSE" | jq -r '.trackSummary.distance')
    
    # Validate required fields
    if [ "$track_date" = "null" ] || [ -z "$track_date" ]; then
        echo "Error: Invalid or missing date in response"
        return 1
    fi
    
    if [ "$activity_type" = "null" ] || [ -z "$activity_type" ]; then
        echo "Error: Invalid or missing activity type in response"
        return 1
    fi
    
    if [ "$distance" = "null" ] || [ -z "$distance" ]; then
        echo "Error: Invalid or missing distance in response"
        return 1
    fi

    # Convert distance from meters to kilometers
    distance=$(echo "scale=2; $distance / 1000" | bc)
    
    # Get timestamp for the record
    local timestamp=$(date -d "$(echo $track_date | cut -d'-' -f1)" +%s)
    
    # Normalize activity type
    local normalized_activity=$(normalize_activity_type "$activity_type")
    
    echo "Processing upload with date: $track_date, type: $normalized_activity, distance: $distance km"

    # Verify that CHALLENGES_RESPONSE contains valid JSON
    if ! echo "$CHALLENGES_RESPONSE" | jq empty 2>/dev/null; then
        echo "Error: Invalid challenges response"
        return 1
    fi

    # Iterate through each challenge
    echo "$CHALLENGES_RESPONSE" | jq -c '.[]' | while read -r challenge; do
        local challenge_id=$(echo "$challenge" | jq -r '.challenge_id')
        local challenge_from=$(echo "$challenge" | jq -r '.from')
        local challenge_to=$(echo "$challenge" | jq -r '.to')
        local challenge_type=$(echo "$challenge" | jq -r '.type')
        
        # Validate challenge data
        if [ "$challenge_id" = "null" ] || [ "$challenge_from" = "null" ] || [ "$challenge_to" = "null" ] || [ "$challenge_type" = "null" ]; then
            echo "Warning: Skipping challenge with invalid data"
            continue
        fi
        
        echo "Checking challenge ID $challenge_id ($challenge_from to $challenge_to, type: $challenge_type)"
        
        # Check if date is in range and activity types match
        if is_date_in_range "$track_date" "$challenge_from" "$challenge_to"; then
            if [ "$(normalize_activity_type "$challenge_type")" == "$normalized_activity" ]; then
                echo "Match found! Submitting record for challenge $challenge_id"
                
                # Submit record using curl
                curl "${CHALLENGES_URL}/challenge_records" -X POST \
                    -H "Authorization: Bearer $TOKEN" \
                    -H "Content-Type: application/json" \
                    -d "{
                        \"challenge_id\": $challenge_id,
                        \"timestamp\": $timestamp,
                        \"type\": \"$normalized_activity\",
                        \"distance\": $distance
                    }"
                
                echo "Record submitted for challenge $challenge_id"
            else
                echo "Activity type mismatch for challenge $challenge_id"
            fi
        else
            echo "Date out of range for challenge $challenge_id"
        fi
    done
}

# Main execution
get_challenge_token

if [ $? -eq 0 ]; then
    get_user_challenges
    
    # Verify that we have a valid response before processing
    if [ -z "$RESPONSE" ]; then
        echo "Error: No response data to process"
        exit 1
    fi
    
    if [ -z "$CHALLENGES_RESPONSE" ]; then
        echo "Error: No challenges data available"
        exit 1
    fi
    
    process_upload "$RESPONSE" "$CHALLENGES_RESPONSE" "$TOKEN"
else
    echo "Failed to get token, aborting..."
    exit 1
fi