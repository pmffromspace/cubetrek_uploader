#!/bin/bash

# Get login credentials and server URL from environment variables
EMAIL=${EMAIL}
PASSWORD=${PASSWORD}
SERVER_URL=${SERVER_URL}
CHALLENGES_ENABLED=${CHALLENGES_ENABLED}

# Login to the server and save cookies
echo "Logging in to $SERVER_URL..."
curl -c /app/cookies.txt -d "email=${EMAIL}&password=${PASSWORD}" \
     -X POST "${SERVER_URL}/login"

if [ $? -ne 0 ]; then
    echo "Login failed. Exiting."
    exit 1
fi

echo "Login successful. Watching for new files in /app/uploads..."

# Function to upload a file
upload_file() {
    local file_path="$1"
    local file_name=$(basename "$file_path")

    echo "Uploading $file_name..."

    # Capture the response from the curl command
    response=$(curl -s -b /app/cookies.txt -F "file=@${file_path}" \
                   -X POST "${SERVER_URL}/upload")

    # Check if curl command succeeded
    if [ $? -eq 0 ]; then
        echo "File $file_name uploaded successfully."
        echo "Response: $response"

        # Move the file to the alreadyimported directory
        mv "$file_path" /app/alreadyimported/
        echo "$file_name moved to alreadyimported."

        # Check if CHALLENGES_ENABLED is set to "true"
        if [ "$CHALLENGES_ENABLED" = "true" ]; then
            # Run update_challenges.sh with the response as an argument
            /app/update_challenges.sh "$response"
        else
            # Output a message if challenges are disabled
            echo "Challenges are disabled."
        fi
    else
        echo "Failed to upload $file_name."
        echo "Response: $response"
    fi
}


# Function to check if a file is still being written
is_file_complete() {
    local file_path="$1"
    local initial_size
    local new_size

    # Check if file exists; if not, return as incomplete
    if [ ! -e "$file_path" ]; then
        return 1  # File does not exist
    fi

    initial_size=$(stat --format="%s" "$file_path" 2>/dev/null)
    sleep 1

    # Check again if file still exists after the delay
    if [ ! -e "$file_path" ]; then
        return 1  # File disappeared
    fi

    new_size=$(stat --format="%s" "$file_path" 2>/dev/null)

    # If file size is unchanged, it means file writing is done
    if [ "$initial_size" -eq "$new_size" ]; then
        return 0  # File is complete
    else
        return 1  # File is still being written
    fi
}

# Function to check if file already exists in alreadyimported
is_duplicate_file() {
    local file_path="$1"
    local file_name=$(basename "$file_path")
    local file_size=$(stat --format="%s" "$file_path")

    # Check for files with same name and size in alreadyimported
    for imported_file in /app/alreadyimported/*; do
        if [ -f "$imported_file" ]; then
            local imported_name=$(basename "$imported_file")
            local imported_size=$(stat --format="%s" "$imported_file")

            if [[ "$imported_name" == "$file_name" && "$imported_size" -eq "$file_size" ]]; then
                return 0  # Duplicate found
            fi
        fi
    done

    return 1  # No duplicate
}

# Function to check and process files with the correct extension
process_files() {
    for file_path in /app/uploads/*; do
        if [ -f "$file_path" ]; then
            local file_name=$(basename "$file_path")

            # Ignore hidden or temporary files
            if [[ "$file_name" =~ ^\. ]]; then
                echo "Ignoring $file_name (hidden or temporary file)."
                continue
            fi

            # Only process files with .fit, .gpx, or .zip extensions
            if [[ "$file_name" =~ \.(fit|gpx|zip)$ ]]; then
                echo "Checking file $file_name..."

                # Wait until the file is fully written
                while ! is_file_complete "$file_path"; do
                    echo "Waiting for $file_name to finish copying..."
                    sleep 2
                done

                # Check for duplicates
                if is_duplicate_file "$file_path"; then
                    echo "Duplicate file found: $file_name. Removing..."
                    rm "$file_path"
                    continue
                fi

                echo "$file_name is fully copied. Proceeding with upload..."
                upload_file "$file_path"
            else
                echo "Ignoring $file_name (not a .fit, .gpx, or .zip file)."
            fi
        fi
    done
}

# Watch the /app/uploads directory for new files and process existing ones
inotifywait -m -e create --format "%f" /app/uploads | while read new_file; do
    file_path="/app/uploads/$new_file"

    # Ignore hidden or temporary files
    if [[ "$new_file" =~ ^\. ]]; then
        echo "Ignoring $new_file (hidden or temporary file)."
        continue
    fi

    # Only process files with .fit, .gpx, or .zip extensions
    if [[ "$new_file" =~ \.(fit|gpx|zip)$ ]]; then
        echo "Detected new file $new_file. Waiting for it to finish copying..."

        # Wait until the file is fully written
        while ! is_file_complete "$file_path"; do
            echo "Waiting for $new_file to finish copying..."
            sleep 2
        done

        # Check for duplicates
        if is_duplicate_file "$file_path"; then
            echo "Duplicate file found: $new_file. Removing..."
            rm "$file_path"
            continue
        fi

        echo "$new_file is fully copied. Proceeding with upload..."
        upload_file "$file_path"

    else
        echo "Ignoring $new_file (not a .fit, .gpx, or .zip file)."
    fi
done &  # Run inotifywait in the background to allow periodic checks

# Periodically check for existing files every 30 seconds
while true; do
    echo "Performing periodic file check..."
    process_files
    sleep 30  # Wait for 30 seconds before the next check
done