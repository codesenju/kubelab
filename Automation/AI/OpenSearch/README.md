# OpenSearch Connector for LM Studio

This tutorial shows how to connect OpenSearch ML Commons to a local LM Studio endpoint, register the remote model, deploy it, and test inference.

## 1. Create the connector

Use OpenSearch ML Commons to create a connector that targets LM Studio's OpenAI-compatible chat API.

```http
POST /_plugins/_ml/connectors/_create
{
  "name": "lmstudio-gemma-chat",
  "description": "LM Studio OpenAI-compatible chat endpoint",
  "version": 1,
  "protocol": "http",
  "parameters": {
    "endpoint": "localhost:1234",
    "model": "google/gemma-4-e2b",
    "temperature": 0.2
  },
  "credential": {
    "openAI_key": "dummy"
  },
  "actions": [
    {
      "action_type": "predict",
      "method": "POST",
      "url": "http://${parameters.endpoint}/v1/chat/completions",
      "headers": {
        "Content-Type": "application/json",
        "Authorization": "Bearer ${credential.openAI_key}"
      },
      "request_body": "{ \"model\": \"${parameters.model}\", \"messages\": ${parameters.messages}, \"temperature\": ${parameters.temperature} }"
    }
  ]
}
```

Notes:

- `endpoint` should point to your local LM Studio server.
- `model` should match the model name loaded in LM Studio.
- `openAI_key` is a placeholder here because LM Studio commonly accepts any bearer token when running locally.

## 2. Register the model

Register a remote model that uses the connector you created.

```http
POST /_plugins/_ml/models/_register
{
  "name": "local-lmstudio-gemma",
  "function_name": "remote",
  "description": "LM Studio Gemma via OpenAI-compatible API",
  "connector_id": "jOZEy50BPzCS7sIOEfNg"
}
```

Replace `connector_id` with the actual ID returned when the connector is created.

## 3. Deploy the model

Deploy the registered model before using it for inference.

```http
POST /_plugins/_ml/models/7-ZGy50BPzCS7sIOLfRz/_deploy
```

Replace the model ID with the ID returned from the registration step.

## 4. Run a prediction

Send a prompt through the deployed model.

```http
POST /_plugins/_ml/models/7-ZGy50BPzCS7sIOLfRz/_predict
{
  "parameters": {
    "messages": [
      {
        "role": "user",
        "content": "Say hello"
      }
    ]
  }
}
```

## Request flow

1. Create the connector.
2. Register the remote model with the connector ID.
3. Deploy the model.
4. Call `_predict` with chat messages.

## Troubleshooting

- If OpenSearch returns an auth or connection error, verify that LM Studio is running on `localhost:1234`.
- If prediction fails, confirm that the connector URL matches the chat completions endpoint and that the model name is valid in LM Studio.
- If you change the connector or model, use the new returned IDs instead of the example IDs in this guide.
