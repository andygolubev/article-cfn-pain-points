FROM --platform=linux/arm64 public.ecr.aws/lambda/python:3.13
LABEL name=lambda/python/clamav
LABEL version=1.0

RUN dnf -y update \
 && dnf -y install clamav1.4 clamav1.4-update clamd1.4 \
 && dnf clean all \
 && pip3 install --no-cache-dir cffi awslambdaric boto3 requests aws-lambda-powertools

RUN freshclam
COPY antivirus_scanner.py ${LAMBDA_TASK_ROOT}

CMD [ "antivirus_scanner.lambda_handler" ]