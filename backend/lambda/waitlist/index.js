"use strict";

const AWS = require("aws-sdk");

const dynamodb = new AWS.DynamoDB.DocumentClient();

const TABLE_WISHLIST = process.env.TABLE_WISHLIST || "wishlist";
const ALLOWED_ORIGIN = process.env.ALLOWED_ORIGIN || "*";

const jsonResponse = (statusCode, body) => ({
  statusCode,
  headers: {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
    "Access-Control-Allow-Headers": "content-type",
    "Access-Control-Allow-Methods": "POST,OPTIONS",
  },
  body: JSON.stringify(body),
});

const isValidEmail = (value) =>
  typeof value === "string" &&
  value.length <= 320 &&
  /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);

exports.handler = async (event) => {
  try {
    const rawBody = event && typeof event.body === "string" ? event.body : "{}";
    const body = JSON.parse(rawBody);
    const email = (body.email || "").trim().toLowerCase();

    if (!isValidEmail(email)) {
      return jsonResponse(400, { error: "Invalid email." });
    }

    const now = new Date().toISOString();
    const sourceIp =
      event?.requestContext?.http?.sourceIp ||
      event?.requestContext?.identity?.sourceIp ||
      "unknown";

    const params = {
      TableName: TABLE_WISHLIST,
      Item: {
        email,
        createdAt: now,
        sourceIp,
      },
      ConditionExpression: "attribute_not_exists(email)",
    };

    try {
      await dynamodb.put(params).promise();
      return jsonResponse(200, { ok: true, status: "created" });
    } catch (error) {
      if (error && error.code === "ConditionalCheckFailedException") {
        return jsonResponse(200, { ok: true, status: "exists" });
      }
      throw error;
    }
  } catch (error) {
    console.error("waitlist handler error", error);
    return jsonResponse(500, { error: "Internal server error." });
  }
};
