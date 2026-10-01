#!/bin/bash

# ================= CONFIGURATION =================
REGION="ap-southeast-1"
TAG_KEY="aws-apn-id"
TAG_VALUE="pc:692392mki9axqgrknb1fcroue"
# =================================================

export AWS_PAGER=""

# Disable auto-retry so the script can immediately detect if it hits the API limit
export AWS_MAX_ATTEMPTS=1 

TOKEN=""
TOTAL_PROCESSED=0
SKIPPED=0

echo "Starting FAST BATCH TAGGING (20 resources/request) in $REGION..."
echo "Note: The script will AUTOMATICALLY STOP if it hits the API Limit."
echo "------------------------------------------------------------"

while true; do
    if [ -z "$TOKEN" ]; then
        RESPONSE=$(aws resourcegroupstaggingapi get-resources --region "$REGION" --output json)
    else
        RESPONSE=$(aws resourcegroupstaggingapi get-resources --region "$REGION" --pagination-token "$TOKEN" --output json)
    fi

    # SMART FILTER: Ambil ARN yang belum punya tag ATAU punya tag tapi valuenya salah. Abaikan EKS pods/services.
    ARNS=($(echo "$RESPONSE" | jq -r --arg key "$TAG_KEY" --arg val "$TAG_VALUE" '.ResourceTagMappingList[] | select(.Tags == null or (any(.Tags[]; .Key == $key and .Value == $val) | not)) | .ResourceARN' | grep -vEi ":pod/|:service/|:replicaset/|:endpointslice/|:deployment/|:ingress/|:persistentvolume/"))

    # Hitung jumlah resource yang dilewati (sudah sesuai atau tidak didukung)
    TOTAL_IN_PAGE=$(echo "$RESPONSE" | jq -r '.ResourceTagMappingList | length')
    SKIPPED_IN_PAGE=$((TOTAL_IN_PAGE - ${#ARNS[@]}))
    SKIPPED=$((SKIPPED + SKIPPED_IN_PAGE))

    if [ ${#ARNS[@]} -gt 0 ]; then
        for ((i=0; i<${#ARNS[@]}; i+=20)); do
            BATCH=("${ARNS[@]:i:20}")
            
            echo "Processing tags for resources $((TOTAL_PROCESSED + 1)) to $((TOTAL_PROCESSED + ${#BATCH[@]}))..."
            
            # Capture all output into a variable
            TAG_RESULT=$(aws resourcegroupstaggingapi tag-resources \
                --region "$REGION" \
                --resource-arn-list "${BATCH[@]}" \
                --tags "${TAG_KEY}=${TAG_VALUE}" 2>&1)
            
            # Detect various limit/throttle keywords from AWS
            if echo "$TAG_RESULT" | grep -qEi "Throttling|Rate exceeded|RequestLimitExceeded|throttled"; then
                echo ""
                echo "🚨 STOP! AWS API Limit Detected."
                echo "Error Detail: $TAG_RESULT"
                echo "Script forcibly stopped to prevent account block/suspension."
                exit 1
            fi
            
            # Show output ONLY if there's an error other than "empty"
            if ! echo "$TAG_RESULT" | grep -q '"FailedResourcesMap": {}'; then
                echo "$TAG_RESULT"
            fi
            
            TOTAL_PROCESSED=$((TOTAL_PROCESSED + ${#BATCH[@]}))
        done
    fi

    TOKEN=$(echo "$RESPONSE" | jq -r '.PaginationToken')

    if [ "$TOKEN" == "null" ] || [ -z "$TOKEN" ]; then
        break
    fi
done

echo "------------------------------------------------------------"
echo "🎉 Done! Successfully processed $TOTAL_PROCESSED resources."
echo "⏩ Skipped $SKIPPED resources (already tagged correctly or unsupported EKS resources)."
