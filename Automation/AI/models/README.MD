## Models that can run on Macbook Air 13" M4 16GB
| Model type                   | Example MLX model                                      | Key notes                                                                                                 |
| ---------------------------- | ------------------------------------------------------ | --------------------------------------------------------------------------------------------------------- |
| **lm (language model)**      | **Mistral-7B-v0.3-4bit**                               | Quantised 7 B-param language model for text generation; safetensors format; runs via `mlx-openai-server`. |
| **multimodal (vision+text)** | **deepseek-vl-7b-chat-4bit**                           | Vision-language chat model (text & image input/output); uses safetensors.                                 |
| **image-generation**         | **Stable Diffusion XL (sd-xl-turbo)** (MLX conversion) | Diffusion model for generating images; runs via MLX image tools.                                          |
| **image-edit**               | **Instruct-Pix2Pix (MLX)**                             | Model for editing images via text prompts (in-painting & modifications).                                  |
| **embeddings**               | **all-MiniLM-L6-v2-4bit**                              | Compact transformer for generating text embeddings; available through the `mlx-embeddings` library.       |
| **whisper (speech-to-text)** | **whisper-large-v3-mlx**                               | OpenAI Whisper speech recognition model converted to MLX; use via `mlx-whisper` for audio transcription.  |
