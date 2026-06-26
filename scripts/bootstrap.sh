#!/usr/bin/env bash
set -e   # si algo falla, para el script no sigue con errores

BUCKET="bookslot-dev-tfstate-th33"
REGION="eu-west-1"

echo "Creando bucket de estado: $BUCKET"

# 1. Crear el bucket
aws s3api create-bucket \
  --bucket "$BUCKET" \
  --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION"

# 2. Activar versionado (recomendado para el tfstate: historial de estados)
aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

echo "✅ Bucket listo. Ahora "git push origin main" para que el pipeline se despliegue"