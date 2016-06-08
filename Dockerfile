FROM alpine:3.4
RUN apk add --update curl && rm -rf /var/cache/apk/*
ENTRYPOINT ["curl", "-sL", "https://git.io/vVk8S"]
