# BEO — VPS Deployment Guide

## 1. Provision your VPS
Minimum: 2 vCPU, 4 GB RAM (Hetzner CAX11 or CX22).
Install Docker: https://docs.docker.com/engine/install/ubuntu/

## 2. Set up a GitHub deploy key
```bash
# On the VPS
ssh-keygen -t ed25519 -C "beo-deploy" -f ~/.ssh/beo_deploy -N ""
cat ~/.ssh/beo_deploy.pub
```
Add the public key to: GitHub repo → Settings → Deploy keys (read-only).

```bash
cat >> ~/.ssh/config << EOF
Host github.com
  IdentityFile ~/.ssh/beo_deploy
  IdentitiesOnly yes
EOF
```

## 3. Clone and configure
```bash
git clone git@github.com:YOUR_USERNAME/beo.git ~/beo
cd ~/beo
cp .env.example .env && nano .env
cp openclaw.json.example openclaw.json
```

## 4. Launch
```bash
docker compose up -d
docker compose logs -f
```

## 5. Deploy updates
```bash
git pull origin main && docker compose up -d --no-build
```

## 6. Agent profile backups (BLU-32)
```bash
crontab -e
# Add:
# 0 3 * * * cp -r ~/.openclaw/agents ~/.openclaw/backups/agents-$(date +\%F) && find ~/.openclaw/backups -name "agents-*" -mtime +30 -exec rm -rf {} +
```
