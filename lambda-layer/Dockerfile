FROM python:3.13 as builder

WORKDIR /build

COPY requirements.txt ./
RUN pip install --target ./python -r requirements.txt
COPY ./*.py ./python/

FROM alpine:latest as packager
COPY --from=builder /build/python /python
WORKDIR /
RUN apk add zip && zip -r lambda_layer.zip python

## The result is lambda_layer.zip that should be uploaded S3 bucket