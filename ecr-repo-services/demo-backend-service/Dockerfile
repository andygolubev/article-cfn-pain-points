# Start from the official Go image
FROM golang:1.25-trixie AS build

WORKDIR /app

COPY main.go .

RUN go build -o helloapp main.go

# Start with a minimal base image
FROM debian:trixie-slim

COPY --from=build /app/helloapp /helloapp

EXPOSE 8080

# Install curl for ECS container healthchecks
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ENTRYPOINT ["/helloapp"]
