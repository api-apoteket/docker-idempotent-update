FROM python:3.13-alpine
RUN apk add --no-cache docker-cli docker-cli-compose msmtp rclone
WORKDIR /app
COPY msmtprc.template backup.conf.template /etc/
COPY src/ ./src/
ENTRYPOINT ["python3", "-m", "src.entrypoint"]
