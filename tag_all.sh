#!/bin/bash

# ================= KONFIGURASI =================
REGION="ap-southeast-1"
TAG_KEY="aws-apn-id"
TAG_VALUE="692392mki9axqgrknb1fcroue"
# ===============================================

export AWS_PAGER=""
export AWS_MAX_ATTEMPTS=1 

TOKEN=""
TOTAL_PROCESSED=0
SKIPPED=0

echo "Memulai proses TAGGING BATCH 20 (Smart Resume) di $REGION..."
echo "Catatan: Mengabaikan resource EKS (Pod/Service dll) yang tidak didukung AWS Tagging."
echo "------------------------------------------------------------"

while true; do
    if [ -z "$TOKEN" ]; then
        RESPONSE=$(aws resourcegroupstaggingapi get-resources --region "$REGION" --output json)
    else
        RESPONSE=$(aws resourcegroupstaggingapi get-resources --region "$REGION" --pagination-token "$TOKEN" --output json)
    fi

    # SMART FILTER: Ambil ARN untagged, lalu buang (grep -v) ARN EKS yang pasti error
    ARNS=($(echo "$RESPONSE" | jq -r --arg key "$TAG_KEY" '.ResourceTagMappingList[] | select(.Tags == null or all(.Tags[]; .Key != $key)) | .ResourceARN' | grep -vEi ":pod/|:service/|:replicaset/|:endpointslice/|:deployment/|:ingress/|:persistentvolume/"))
    
    TOTAL_IN_PAGE=$(echo "$RESPONSE" | jq -r '.ResourceTagMappingList | length')
    SKIPPED_IN_PAGE=$((TOTAL_IN_PAGE - ${#ARNS[@]}))
    SKIPPED=$((SKIPPED + SKIPPED_IN_PAGE))

    if [ ${#ARNS[@]} -gt 0 ]; then
        for ((i=0; i<${#ARNS[@]}; i+=20)); do
            BATCH=("${ARNS[@]:i:20}")
            
            echo "Memproses tag untuk resource ke-$((TOTAL_PROCESSED + 1)) sampai $((TOTAL_PROCESSED + ${#BATCH[@]}))..."
            
            TAG_RESULT=$(aws resourcegroupstaggingapi tag-resources \
                --region "$REGION" \
                --resource-arn-list "${BATCH[@]}" \
                --tags "${TAG_KEY}=${TAG_VALUE}" 2>&1)
            
            if echo "$TAG_RESULT" | grep -qEi "Throttling|Rate exceeded|RequestLimitExceeded|throttled"; then
                echo ""
                echo "🚨 STOP! Terdeteksi API Limit dari AWS."
                echo "Detail Error: $TAG_RESULT"
                echo "Tunggu 3-5 menit, lalu jalankan lagi untuk Melanjutkan (Resume)."
                exit 1
            fi
            
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
echo "🎉 Selesai! Berhasil men-tag $TOTAL_PROCESSED resource."
echo "⏩ Melewati $SKIPPED resource (sudah di-tag / tidak didukung)."
