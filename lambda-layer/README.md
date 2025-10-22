docker buildx build --load --platform=linux/arm64 -t lambda-layer-builder .
docker create --name extract-layer lambda-layer-builder
docker cp extract-layer:/lambda_layer.zip ./
docker rm extract-layer