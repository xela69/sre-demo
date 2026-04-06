#!/bin/bash

MAX_ATTEMPTS=60
SLEEP_SECONDS=15
ATTEMPT=1
DEPLOYMENT_NAME="firewallModule"
RESOURCE_GROUP="networkRG"

# Capture start time in seconds since epoch
START_TIME=$(date +%s)

while true; do
  timestamp=$(date '+%Y-%m-%d %H:%M')
  CURRENT_TIME=$(date +%s)
  DURATION=$((CURRENT_TIME - START_TIME))
  hours=$((DURATION / 3600))
  mins=$(((DURATION % 3600) / 60))
  RUNTIME=$(printf "%02d:%02d" $hours $mins)

  status=$(az deployment group list \
    --resource-group "$RESOURCE_GROUP" \
    --query "[?name=='$DEPLOYMENT_NAME'].properties.provisioningState" \
    --output tsv)

  echo "[$timestamp] Attempt $ATTEMPT: provisioningState = $status | Elapsed: $RUNTIME (HH:MM)"

  if [[ "$status" == "Succeeded" || "$status" == "Failed" ]]; then
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    hours=$((DURATION / 3600))
    mins=$(((DURATION % 3600) / 60))
    ELAPSED=$(printf "%02d:%02d" $hours $mins)

    if [[ "$status" == "Succeeded" ]]; then
      echo "[$timestamp] ✅ Provisioning succeeded in $ELAPSED (HH:MM)."
      break
    else
      echo "[$timestamp] ❌ Provisioning failed after $ELAPSED (HH:MM). Exiting."
      exit 1
    fi
  fi

  if [[ $ATTEMPT -ge $MAX_ATTEMPTS ]]; then
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    hours=$((DURATION / 3600))
    mins=$(((DURATION % 3600) / 60))
    ELAPSED=$(printf "%02d:%02d" $hours $mins)

    echo "[$timestamp] ⚠️ Timeout after $ELAPSED (HH:MM) waiting for deployment to complete."
    exit 1
  fi

  ((ATTEMPT++))
  sleep "$SLEEP_SECONDS"
done

# Final summary
az deployment group show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$DEPLOYMENT_NAME" \
  --query "{Name:name, Status:properties.provisioningState, Timestamp:properties.timestamp}" \
  --output table