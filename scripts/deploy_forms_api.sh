#!/usr/bin/env bash
set -euo pipefail

REGION="${AWS_REGION:-ap-southeast-2}"
TABLE_EMAILS="${TABLE_EMAILS:-emails}"
TABLE_WISHLIST="${TABLE_WISHLIST:-wishlist}"
ROLE_NAME="${ROLE_NAME:-sabz-forms-lambda-role}"
WAITLIST_FN="${WAITLIST_FN:-sabz-waitlist-handler}"
CONTACT_FN="${CONTACT_FN:-sabz-contact-handler}"
API_NAME="${API_NAME:-sabz-forms-api}"
ALLOWED_ORIGIN="${ALLOWED_ORIGIN:-*}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="${ROOT_DIR}/.aws-deploy"
mkdir -p "${TMP_DIR}"

ACCOUNT_ID="$(aws sts get-caller-identity --region "${REGION}" --query 'Account' --output text)"
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
TABLE_EMAILS_ARN="arn:aws:dynamodb:${REGION}:${ACCOUNT_ID}:table/${TABLE_EMAILS}"
TABLE_WISHLIST_ARN="arn:aws:dynamodb:${REGION}:${ACCOUNT_ID}:table/${TABLE_WISHLIST}"

echo "Using account: ${ACCOUNT_ID}"
echo "Using region:  ${REGION}"

ensure_email_table() {
  local table_name="$1"
  if aws dynamodb describe-table --table-name "${table_name}" --region "${REGION}" >/dev/null 2>&1; then
    echo "Table '${table_name}' exists."
  else
    echo "Creating table '${table_name}' (PK: email)..."
    aws dynamodb create-table \
      --table-name "${table_name}" \
      --attribute-definitions AttributeName=email,AttributeType=S \
      --key-schema AttributeName=email,KeyType=HASH \
      --billing-mode PAY_PER_REQUEST \
      --region "${REGION}" >/dev/null
  fi
  aws dynamodb wait table-exists --table-name "${table_name}" --region "${REGION}"
}

ensure_email_table "${TABLE_EMAILS}"
ensure_email_table "${TABLE_WISHLIST}"

cat > "${TMP_DIR}/trust-policy.json" <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
JSON

if aws iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
  echo "IAM role '${ROLE_NAME}' exists."
else
  echo "Creating IAM role '${ROLE_NAME}'..."
  aws iam create-role \
    --role-name "${ROLE_NAME}" \
    --assume-role-policy-document "file://${TMP_DIR}/trust-policy.json" >/dev/null
fi

aws iam attach-role-policy \
  --role-name "${ROLE_NAME}" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole >/dev/null || true

cat > "${TMP_DIR}/ddb-policy.json" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DynamoDbAccessForForms",
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:GetItem"
      ],
      "Resource": [
        "${TABLE_EMAILS_ARN}",
        "${TABLE_WISHLIST_ARN}"
      ]
    }
  ]
}
JSON

aws iam put-role-policy \
  --role-name "${ROLE_NAME}" \
  --policy-name sabz-forms-dynamodb-access \
  --policy-document "file://${TMP_DIR}/ddb-policy.json" >/dev/null

echo "Installing Lambda dependencies..."
npm install --omit=dev --prefix "${ROOT_DIR}/backend/lambda/waitlist" >/dev/null
npm install --omit=dev --prefix "${ROOT_DIR}/backend/lambda/contact" >/dev/null

rm -f "${TMP_DIR}/waitlist.zip" "${TMP_DIR}/contact.zip"
(cd "${ROOT_DIR}/backend/lambda/waitlist" && zip -q -r "${TMP_DIR}/waitlist.zip" index.js package.json node_modules)
(cd "${ROOT_DIR}/backend/lambda/contact" && zip -q -r "${TMP_DIR}/contact.zip" index.js package.json node_modules)

sleep 10

upsert_waitlist_lambda() {
  if aws lambda get-function --function-name "${WAITLIST_FN}" --region "${REGION}" >/dev/null 2>&1; then
    echo "Updating Lambda '${WAITLIST_FN}'..."
    aws lambda update-function-code \
      --function-name "${WAITLIST_FN}" \
      --zip-file "fileb://${TMP_DIR}/waitlist.zip" \
      --region "${REGION}" >/dev/null
    aws lambda wait function-updated-v2 --function-name "${WAITLIST_FN}" --region "${REGION}"
    aws lambda update-function-configuration \
      --function-name "${WAITLIST_FN}" \
      --runtime nodejs20.x \
      --handler index.handler \
      --role "${ROLE_ARN}" \
      --timeout 10 \
      --environment "Variables={TABLE_WISHLIST=${TABLE_WISHLIST},ALLOWED_ORIGIN=${ALLOWED_ORIGIN}}" \
      --region "${REGION}" >/dev/null
    aws lambda wait function-updated-v2 --function-name "${WAITLIST_FN}" --region "${REGION}"
  else
    echo "Creating Lambda '${WAITLIST_FN}'..."
    aws lambda create-function \
      --function-name "${WAITLIST_FN}" \
      --runtime nodejs20.x \
      --role "${ROLE_ARN}" \
      --handler index.handler \
      --timeout 10 \
      --zip-file "fileb://${TMP_DIR}/waitlist.zip" \
      --environment "Variables={TABLE_WISHLIST=${TABLE_WISHLIST},ALLOWED_ORIGIN=${ALLOWED_ORIGIN}}" \
      --region "${REGION}" >/dev/null
  fi
  aws lambda wait function-active-v2 --function-name "${WAITLIST_FN}" --region "${REGION}"
}

upsert_contact_lambda() {
  if aws lambda get-function --function-name "${CONTACT_FN}" --region "${REGION}" >/dev/null 2>&1; then
    echo "Updating Lambda '${CONTACT_FN}'..."
    aws lambda update-function-code \
      --function-name "${CONTACT_FN}" \
      --zip-file "fileb://${TMP_DIR}/contact.zip" \
      --region "${REGION}" >/dev/null
    aws lambda wait function-updated-v2 --function-name "${CONTACT_FN}" --region "${REGION}"
    aws lambda update-function-configuration \
      --function-name "${CONTACT_FN}" \
      --runtime nodejs20.x \
      --handler index.handler \
      --role "${ROLE_ARN}" \
      --timeout 10 \
      --environment "Variables={TABLE_EMAILS=${TABLE_EMAILS},ALLOWED_ORIGIN=${ALLOWED_ORIGIN}}" \
      --region "${REGION}" >/dev/null
    aws lambda wait function-updated-v2 --function-name "${CONTACT_FN}" --region "${REGION}"
  else
    echo "Creating Lambda '${CONTACT_FN}'..."
    aws lambda create-function \
      --function-name "${CONTACT_FN}" \
      --runtime nodejs20.x \
      --role "${ROLE_ARN}" \
      --handler index.handler \
      --timeout 10 \
      --zip-file "fileb://${TMP_DIR}/contact.zip" \
      --environment "Variables={TABLE_EMAILS=${TABLE_EMAILS},ALLOWED_ORIGIN=${ALLOWED_ORIGIN}}" \
      --region "${REGION}" >/dev/null
  fi
  aws lambda wait function-active-v2 --function-name "${CONTACT_FN}" --region "${REGION}"
}

upsert_waitlist_lambda
upsert_contact_lambda

API_ID="$(aws apigatewayv2 get-apis --region "${REGION}" --query "Items[?Name=='${API_NAME}'].ApiId | [0]" --output text)"

if [[ "${API_ID}" == "None" ]]; then
  cat > "${TMP_DIR}/create-api.json" <<JSON
{
  "Name": "${API_NAME}",
  "ProtocolType": "HTTP",
  "CorsConfiguration": {
    "AllowOrigins": ["${ALLOWED_ORIGIN}"],
    "AllowMethods": ["POST", "OPTIONS"],
    "AllowHeaders": ["content-type"],
    "MaxAge": 300
  }
}
JSON
  echo "Creating API Gateway HTTP API '${API_NAME}'..."
  API_ID="$(aws apigatewayv2 create-api --region "${REGION}" --cli-input-json "file://${TMP_DIR}/create-api.json" --query 'ApiId' --output text)"
else
  echo "Using existing API '${API_NAME}' (${API_ID})."
fi

WAITLIST_FN_ARN="$(aws lambda get-function --function-name "${WAITLIST_FN}" --region "${REGION}" --query 'Configuration.FunctionArn' --output text)"
CONTACT_FN_ARN="$(aws lambda get-function --function-name "${CONTACT_FN}" --region "${REGION}" --query 'Configuration.FunctionArn' --output text)"

WAITLIST_INT_ID="$(aws apigatewayv2 create-integration \
  --api-id "${API_ID}" \
  --integration-type AWS_PROXY \
  --integration-uri "${WAITLIST_FN_ARN}" \
  --payload-format-version "2.0" \
  --region "${REGION}" \
  --query 'IntegrationId' --output text)"

CONTACT_INT_ID="$(aws apigatewayv2 create-integration \
  --api-id "${API_ID}" \
  --integration-type AWS_PROXY \
  --integration-uri "${CONTACT_FN_ARN}" \
  --payload-format-version "2.0" \
  --region "${REGION}" \
  --query 'IntegrationId' --output text)"

upsert_route() {
  local route_key="$1"
  local integration_id="$2"
  local route_id

  route_id="$(aws apigatewayv2 get-routes --api-id "${API_ID}" --region "${REGION}" --query "Items[?RouteKey=='${route_key}'].RouteId | [0]" --output text)"
  if [[ "${route_id}" == "None" ]]; then
    aws apigatewayv2 create-route \
      --api-id "${API_ID}" \
      --route-key "${route_key}" \
      --target "integrations/${integration_id}" \
      --region "${REGION}" >/dev/null
  else
    aws apigatewayv2 update-route \
      --api-id "${API_ID}" \
      --route-id "${route_id}" \
      --target "integrations/${integration_id}" \
      --region "${REGION}" >/dev/null
  fi
}

upsert_route "POST /waitlist" "${WAITLIST_INT_ID}"
upsert_route "POST /contact" "${CONTACT_INT_ID}"

DEFAULT_STAGE="$(aws apigatewayv2 get-stages --api-id "${API_ID}" --region "${REGION}" --query "Items[?StageName=='\$default'].StageName | [0]" --output text)"
if [[ "${DEFAULT_STAGE}" == "None" ]]; then
  aws apigatewayv2 create-stage \
    --api-id "${API_ID}" \
    --stage-name "\$default" \
    --auto-deploy \
    --region "${REGION}" >/dev/null
else
  aws apigatewayv2 update-stage \
    --api-id "${API_ID}" \
    --stage-name "\$default" \
    --auto-deploy \
    --region "${REGION}" >/dev/null
fi

WAITLIST_PERMISSION_ID="apigw-waitlist-$(date +%s)"
CONTACT_PERMISSION_ID="apigw-contact-$(date +%s)"

aws lambda add-permission \
  --function-name "${WAITLIST_FN}" \
  --statement-id "${WAITLIST_PERMISSION_ID}" \
  --action "lambda:InvokeFunction" \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:${REGION}:${ACCOUNT_ID}:${API_ID}/*/POST/waitlist" \
  --region "${REGION}" >/dev/null || true

aws lambda add-permission \
  --function-name "${CONTACT_FN}" \
  --statement-id "${CONTACT_PERMISSION_ID}" \
  --action "lambda:InvokeFunction" \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:${REGION}:${ACCOUNT_ID}:${API_ID}/*/POST/contact" \
  --region "${REGION}" >/dev/null || true

API_URL="$(aws apigatewayv2 get-api --api-id "${API_ID}" --region "${REGION}" --query 'ApiEndpoint' --output text)"

echo "----------------------------------------------------"
echo "Forms API is ready."
echo "API URL: ${API_URL}"
echo "Set this in Amplify env vars as VITE_API_BASE_URL=${API_URL}"
echo "----------------------------------------------------"
