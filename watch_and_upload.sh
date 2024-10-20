#!/bin/bash

# Get login credentials and server URL from environment variables
EMAIL=${EMAIL}
PASSWORD=${PASSWORD}
SERVER_URL=${SERVER_URL}

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

    # Upload the file
    curl -b /app/cookies.txt -F "file=@${file_path}" \
         -X POST "${SERVER_URL}/upload"

    if [ $? -eq 0 ]; then
        echo "File $file_name uploaded successfully."

        # Move the file to the alreadyimported directory
        mv "$file_path" /app/alreadyimported/
        echo "$file_name moved to alreadyimported."

    else
        echo "Failed to upload $file_name."
    fi
}

# Watch the /app/uploads directory for new .fit, .gpx, or .zip files
inotifywait -m -e create --format "%f" /app/uploads | while read new_file; do
    # Only process files with .fit, .gpx, or .zip extensions
    if [[ "$new_file" =~ \.(fit|gpx|zip)$ ]]; then
        upload_file "/app/uploads/$new_file"
    else
        echo "Ignoring $new_file (not a .fit, .gpx, or .zip file)."
    fi
done

