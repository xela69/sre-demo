#!/bin/bash
# To be run from a VM within Azure Vnets/subnets.

LOG_FILE=LOG_FILE="$HOME/firewall-policy-test.log"
KEYVAULT_FQDN="xelaVault-5nwf.vault.azure.net"
FIREWALL_PUBLIC_IP="4.154.202.203"    # Replace with your firewall's public IP
NAT_TEST_PORT=2223              # Port exposed by NAT rule (optional)

echo "---- Azure Firewall Policy Test Log ----" | tee -a $LOG_FILE
echo "Timestamp: $(date)" | tee -a $LOG_FILE

# ✅ DNS Resolution Test
echo -e "\n🧪 Testing DNS resolution via Azure DNS..." | tee -a $LOG_FILE
dig microsoft.com @168.63.129.16 +short | tee -a $LOG_FILE

# ✅ HTTP/S Allow Test
echo -e "\n🧪 Testing allowed HTTPS access to Microsoft and Key Vault..." | tee -a $LOG_FILE
curl -I https://microsoft.com -m 5 | tee -a $LOG_FILE
curl -I https://$KEYVAULT_FQDN -m 5 | tee -a $LOG_FILE

# 🛑 Blocked Site Test
echo -e "\n🛑 Testing blocked HTTPS access to facebook.com (should fail)..." | tee -a $LOG_FILE
curl -I https://facebook.com -m 5 | tee -a $LOG_FILE || echo "Blocked as expected." | tee -a $LOG_FILE

# ✅ TCP Port Access Test (SSH / RDP)
echo -e "\n🧪 Testing outbound TCP ports (22 & 3389)..." | tee -a $LOG_FILE
nc -zvw3 microsoft.com 22 && echo "SSH allowed" | tee -a $LOG_FILE
nc -zvw3 microsoft.com 3389 && echo "RDP allowed" | tee -a $LOG_FILE

# ✅ NAT Rule Test (Optional)
echo -e "\n🧪 Testing NAT rule access via Firewall public IP on port $NAT_TEST_PORT..." | tee -a $LOG_FILE
nc -zvw3 $FIREWALL_PUBLIC_IP $NAT_TEST_PORT && echo "NAT test successful" | tee -a $LOG_FILE || echo "NAT test failed" | tee -a $LOG_FILE

echo -e "\n✔️ Tests complete. Review log: $LOG_FILE"