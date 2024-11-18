# Use Debian Bookworm Slim as base image
FROM debian:bookworm-slim

# Install required packages: curl and inotify-tools for file watching
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    inotify-tools \
    jq \
    ca-certificates \
    bc \
    && rm -rf /var/lib/apt/lists/*

# Create working directories
RUN mkdir -p /app/uploads /app/alreadyimported

# Copy the script to the container
COPY watch_and_upload.sh /app/watch_and_upload.sh

COPY update_challenges.sh /app/update_challenges.sh

# Make the script executable
RUN chmod +x /app/watch_and_upload.sh
RUN chmod +x /app/update_challenges.sh

# Set environment variables (to be overwritten at runtime)
ENV EMAIL=your_email@example.com
ENV PASSWORD=your_password
ENV SERVER_URL=http://yourserverurl

# Set the default command to run the script
CMD ["/app/watch_and_upload.sh"]

