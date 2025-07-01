# How to add mcp servers to amazon q chat
```json
{
  "mcpServers": {
    "kubernetes": {
      "command": "npx",
      "args": ["-y", "kubernetes-mcp-server@latest"],
      "env": {},
      "timeout": 120000
    }
  }
}
```

ref: https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/qdev-mcp.html