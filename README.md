# OneAPI Gateway (Render deploy)

Deployment repo for [samaidev/oneapi_r](https://github.com/samaidev/oneapi_r) — OneAPI Gateway, an aggregated LLM API gateway (OpenAI/Anthropic/Gemini/DeepSeek/Azure unified endpoint).

This repo packages the official Linux release binary (`oneapi-linux-amd64` from v2.0.0) into a minimal Debian image.

## Deploy on Render

1. New Web Service → Public Git Repository → this repo
2. Runtime: Docker
3. Port: 3000
4. Admin dashboard: `https://<your-service>.onrender.com` (default password: `admin123`)
