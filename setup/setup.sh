#!/bin/bash
set -e
echo "🐾 BEO setup..."
mkdir -p data/redis
mkdir -p data/litellm
touch data/redis/.gitkeep
touch data/litellm/.gitkeep
if [ ! -f .env ]; then
  cp .env.example .env
  echo "📝 .env created from .env.example — fill in your keys before starting."
else
  echo "✅ .env already exists, skipping."
fi
echo "✅ Done. Next: edit .env, then run: docker compose up -d"
