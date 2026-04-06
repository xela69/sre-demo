#!/bin/bash

FIREWALL_PUBLIC_IP="4.154.202.203"  # 🔁 Replace with your Azure Firewall public IP
NAT_PORT=2221                 # 🔁 Replace with your NAT rule port
KEYVAULT_FQDN="xelavault-5nwf.vault.azure.net"  # 🔁 Replace with your Key Vault FQDN
STORAGE_FQDN="eastusxketx.blob.core.windows.net"

echo "---- Azure Firewall External Access Test ----"
echo "Timestamp: $(date)"
echo

# ✅ NAT Rule Test to Internal VM
echo "🧪 Testing NAT rule to internal VM..."
nc -zv $FIREWALL_PUBLIC_IP $NAT_PORT
if [[ $? -eq 0 ]]; then
  echo "✅ NAT port $NAT_PORT open on $FIREWALL_PUBLIC_IP"
else
  echo "❌ NAT port $NAT_PORT failed (check firewall or NSG)"
fi
echo

# ✅ Test access to Azure Key Vault via FQDN
echo "🧪 Testing Key Vault FQDN reachability..."
curl -I https://$KEYVAULT_FQDN -m 5 || echo "❌ Key Vault access failed"
echo

# ✅ Test access to Azure Storage (PaaS)
echo "🧪 Testing Azure Blob Storage FQDN..."
curl -I https://$STORAGE_FQDN -m 5 || echo "❌ Storage access failed"
echo

# ✅ DNS Check using system resolver
echo "🧪 DNS resolution test for Azure services..."
host $KEYVAULT_FQDN
host $STORAGE_FQDN
echo

echo "✔️ Done."