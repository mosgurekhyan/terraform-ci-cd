#!/usr/bin/env bash
set -euo pipefail

KEY_FILE="terraform_key.pem"

if [ -f "$KEY_FILE" ]; then
  echo "SSH key $KEY_FILE already exists — skipping generation."
  exit 0
fi

# Generate a fresh ed25519 keypair, no passphrase
ssh-keygen -t ed25519 -N "" -C "terraform" -f "$KEY_FILE" -q
chmod 600 "$KEY_FILE"

echo "✅ Key generated: $KEY_FILE and ${KEY_FILE}.pub"