# cubetrek auto uploader

This is a docker image for watching a upload directory for new .gpx or .fit files, uploads it to cubetrek (official or selfhosted instance compatible), and if enabled, it also adds matching activities to a selfhosted challenges server.

*Selfhosted open source challenges server:* https://github.com/pmffromspace/fitness-challenges-server


### Usage:
1. **Build the Docker Image**:
   ```bash
   docker build -t cubetrek-uploader .
   ```

2. **Run the Container**:
   ```docker
   docker run -e EMAIL=CUBETREK_USER_EMAIL \
   -e PASSWORD=CUBETREKPASS \
   -e SERVER_URL=https://cubetrek.com \
   -e CHALLENGES_ENABLED=false \
   -e CHALLENGES_USER=user@example.org \
   -e CHALLENGES_URL=https://challenges-api.example.org \
   -e CHALLENGES_PASSWORD=USERPASS \
   -v ./volumes/cubetrek_uploader/uploads:/app/uploads \
   -v ./volumes/cubetrek_uploader/alreadyimported:/app/alreadyimported \
   --name cubetrek-uploader ghcr.io/pmffromspace/cubetrek_uploader:latest
   ```

---

This container will constantly watch the `uploads` directory for new files and upload them one by one, providing detailed logs for debugging. 


This Docker setup creates a container based on Debian Bookworm Slim that automates the process of monitoring a directory for new files and uploading them to a server. Here's what it does:

- Environment Variables for Login: The container retrieves the user email, password, and server URL from environment variables (EMAIL, PASSWORD, SERVER_URL). These values are used to log in to the server using a POST request via curl. The login session is saved in a cookie file (cookies.txt).

- File Monitoring: The container constantly monitors a mounted directory (/app/uploads) for new files with specific extensions: .fit, .gpx, or .zip. It uses inotifywait to detect new files as soon as they are created in the directory.

- File Uploading: When a new file is detected, the container uploads it to the server using a POST request with curl, attaching the file as a form field. The cookies from the login are sent along with the request for authentication.

- Post-Upload Actions: If the file is successfully uploaded, it is moved from the uploads directory to another mounted directory (/app/alreadyimported). This ensures that files are processed one by one, and successful uploads are archived.

- Verbose Logging: The container provides detailed logs during the file upload process for easy debugging, including information on login attempts, file detection, and upload success or failure.
