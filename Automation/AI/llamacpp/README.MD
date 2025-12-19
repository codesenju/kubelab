## Running llm's locally with docker
```bash
pip install -U huggingface-hub
hf version
```
```bash
mkdir -p /opt/dockge/stacks/llamacpp/models/Qwen2.5-Coder-1.5B-Instruct-Q8_0-GGUF

hf download ggml-org/Qwen2.5-Coder-1.5B-Instruct-Q8_0-GGUF   --local-dir /opt/dockge/stacks/llamacpp/models/Qwen2.5-Coder-1.5B-Instruct-Q8_0-GGUF
```
```bash
docker compose up -d
```
```bash
curl -s http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen",
    "messages": [
      { "role": "system", "content": "Be concise." },
      { "role": "user", "content": "Explain Kubernetes in one sentence." }
    ],
    "max_tokens": 40,
    "stop": ["User:", "Qwen:"]
  }' | jq '.choices[0].message.content'

```

## Example Config for Continue VSC Plugin
```yaml
name: Local Config
version: 1.0.0
schema: v1

models:
  - name: qwen2.5-coder
    provider: openai
    model: qwen2.5-coder-1.5b-instruct-q8_0.gguf
    apiBase: http://100.64.0.26:8080/v1
    apiKey: local
    roles:
      - chat
      - edit
      - apply
      - autocomplete
    capabilities:
      - tool_use
```
## RUnning on macos
```bash
LLAMA_CACHE="$HOME/.models/llama.cpp" \
llama-server -hf mradermacher/gpt2-alpaca-gpt4-GGUF:Q8_0
```