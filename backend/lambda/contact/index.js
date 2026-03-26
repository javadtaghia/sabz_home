"use strict";

const AWS = require("aws-sdk");

const dynamodb = new AWS.DynamoDB.DocumentClient();

const TABLE_EMAILS = process.env.TABLE_EMAILS || "emails";
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

    const name = (body.name || "").trim().slice(0, 200);
    const email = (body.email || "").trim().toLowerCase();
    const message = (body.message || "").trim().slice(0, 5000);

    if (!name) {
      return jsonResponse(400, { error: "Name is required." });
    }
    if (!isValidEmail(email)) {
      return jsonResponse(400, { error: "Invalid email." });
    }
    if (!message) {
      return jsonResponse(400, { error: "Message is required." });
    }

    const now = new Date().toISOString();
    const sourceIp =
      event?.requestContext?.http?.sourceIp ||
      event?.requestContext?.identity?.sourceIp ||
      "unknown";

    const newEntry = [
      {
        at: now,
        name,
        message,
        sourceIp,
      },
    ];

    const params = {
      TableName: TABLE_EMAILS,
      Key: { email },
      UpdateExpression:
        "SET #updatedAt = :updatedAt, #latestName = :latestName, #latestMessage = :latestMessage, #messages = list_append(if_not_exists(#messages, :emptyList), :newEntry), #messageCount = if_not_exists(#messageCount, :zero) + :inc",
      ExpressionAttributeNames: {
        "#updatedAt": "updatedAt",
        "#latestName": "latestName",
        "#latestMessage": "latestMessage",
        "#messages": "messages",
        "#messageCount": "messageCount",
      },
      ExpressionAttributeValues: {
        ":updatedAt": now,
        ":latestName": name,
        ":latestMessage": message,
        ":emptyList": [],
        ":newEntry": newEntry,
        ":zero": 0,
        ":inc": 1,
      },
    };

    await dynamodb.update(params).promise();
    return jsonResponse(200, { ok: true });
  } catch (error) {
    console.error("contact handler error", error);
    return jsonResponse(500, { error: "Internal server error." });
  }
};
