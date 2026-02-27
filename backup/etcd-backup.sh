#!/bin/bash

# --- Configuration ---
BACKUP_DIR="/opt/kubernetes/"
KEEP_DAYS=7
TIMESTAMP=$(date +%Y-%m-%d_%Hh%M)
BACKUP_FILE="${BACKUP_DIR}/etcd-snapshot_${TIMESTAMP}.db"
CLUSTER_NAME="kubelab"

# Telegram Config
TOKEN="YOUR_BOT_TOKEN_HERE"
CHAT_ID="YOUR_CHAT_ID_HERE"

# --- Functions ---
send_telegram() {
    local message=$1
    curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        -d text="${message}" \
        -d parse_mode="Markdown" > /dev/null
}

# --- Start Backup ---
mkdir -p "$BACKUP_DIR"
export ETCDCTL_API=3

echo "--- Starting etcd backup: $TIMESTAMP ---"
send_telegram "🚀 *ETCD Backup Started* on \`${CLUSTER_NAME}\`"

# Perform Snapshot
sudo etcdctl snapshot save "$BACKUP_FILE" \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Verify Snapshot
if [ $? -eq 0 ]; then
    FILE_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    
    # Also backup manifests (since you need them for restoration)
    tar -czf "${BACKUP_DIR}/manifests_${TIMESTAMP}.tar.gz" /etc/kubernetes/manifests /etc/kubernetes/pki
    
    echo "Snapshot saved successfully: $FILE_SIZE"
    send_telegram "✅ *ETCD Backup Success*
📌 *Cluster:* \`${CLUSTER_NAME}\`
📄 *File:* \`etcd-snapshot_${TIMESTAMP}.db\`
📦 *Size:* \`${FILE_SIZE}\`
🛠 *Manifests:* Backed up to tar.gz"
else
    echo "ERROR: Snapshot failed!"
    send_telegram "❌ *ETCD Backup FAILED* on \`${CLUSTER_NAME}\`! Check logs immediately."
    exit 1
fi

# Cleanup
echo "Cleaning up old backups..."
find "$BACKUP_DIR" -type f \( -name "*.db" -o -name "*.tar.gz" \) -mtime +$KEEP_DAYS -delete

echo "--- Backup process complete ---"