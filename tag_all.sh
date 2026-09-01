#!/bin/bash

# ================= KONFIGURASI =================
REGION="ap-southeast-1"
TAG_KEY="aws-apn-id"
TAG_VALUE="692392mki9axqgrknb1fcroue"
# ===============================================

export AWS_PAGER=""

# Matikan auto-retry supaya kalau kena limit, script langsung tahu dan bisa berhenti
export AWS_MAX_ATTEMPTS=1 

TOKEN=""
TOTAL_PROCESSED=0

echo "Memulai proses TAGGING BATCH 20 di $REGION..."
echo "Akan menambahkan tag -> Key: $TAG_KEY | Value: $TAG_VALUE"
echo "Catatan: Script akan OTOMATIS BERHENTI jika terkena API Limit."
echo "------------------------------------------------------------"

while true; do
    if [ -z "$TOKEN" ]; then
        RESPONSE=$(aws resourcegroupstaggingapi get-resources --region "$REGION" --output json)
    else
        RESPONSE=$(aws resourcegroupstaggingapi get-resources --region "$REGION" --pagination-token "$TOKEN" --output json)
    fi

    # Masukkan semua ARN di halaman ini ke dalam sebuah Array
    ARNS=($(echo "$RESPONSE" | jq -r '.ResourceTagMappingList[].ResourceARN'))

    if [ ${#ARNS[@]} -gt 0 ]; then
        for ((i=0; i<${#ARNS[@]}; i+=20)); do
            BATCH=("${ARNS[@]:i:20}")
            
            echo "Memproses tag untuk resource ke-$((TOTAL_PROCESSED + 1)) sampai $((TOTAL_PROCESSED + ${#BATCH[@]}))..."
            
            # Eksekusi tagging dan tangkap output/error-nya (2>&1 menggabungkan error ke output standar)
            TAG_RESULT=$(aws resourcegroupstaggingapi tag-resources \
                --region "$REGION" \
                --resource-arn-list "${BATCH[@]}" \
                --tags "${TAG_KEY}=${TAG_VALUE}" 2>&1)
            
            # Cek apakah di dalam output terdapat kata "Throttling" atau "Rate exceeded"
            if echo "$TAG_RESULT" | grep -qEi "Throttling|Rate exceeded"; then
                echo ""
                echo "🚨 STOP! Terdeteksi API Limit (Throttled)."
                echo "Pesan Error AWS: $TAG_RESULT"
                echo "Script dihentikan untuk keamanan."
                exit 1 # Mematikan script sepenuhnya
            fi
            
            # Jika ada error lain (seperti EKS Pod invalid), print saja tapi script tetap lanjut
            if [ -n "$TAG_RESULT" ]; then
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
echo "🎉 Selesai! Berhasil memproses $TOTAL_PROCESSED resource dengan aman."
