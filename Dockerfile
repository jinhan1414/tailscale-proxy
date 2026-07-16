# Stage 1: build the Go status server
FROM golang:1.22-alpine AS builder
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY main.go ./
COPY web/ ./web/
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /out/status-server .

# Stage 2: copy the rclone binary used for Cloudflare R2 state persistence
FROM rclone/rclone:latest AS rclone

# Stage 3: based on the official tailscale image
FROM tailscale/tailscale:latest
COPY --from=builder /out/status-server /usr/local/bin/status-server
COPY --from=rclone /usr/local/bin/rclone /usr/local/bin/rclone
COPY entrypoint.sh /usr/local/bin/custom-entrypoint.sh
# Guard against Windows CRLF line endings breaking the shebang in Linux.
RUN sed -i 's/\r$//' /usr/local/bin/custom-entrypoint.sh && \
    chmod +x /usr/local/bin/custom-entrypoint.sh
ENTRYPOINT ["/usr/local/bin/custom-entrypoint.sh"]
