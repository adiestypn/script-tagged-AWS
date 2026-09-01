Here is the fully translated English version of both the **Bash Script** and the **README.md**.

### 1. The Bash Script (`tag_all.sh`)

You can replace the contents of your file with this English version:

```bash
#!/bin/bash

# ================= CONFIGURATION =================
REGION="ap-southeast-1"
TAG_KEY="aws-apn-id"
TAG_VALUE="692392mki9axqgrknb1fcroue"
# =================================================

export AWS_PAGER=""

# Disable auto-retry so the script can immediately detect if it hits the API limit
export AWS_MAX_ATTEMPTS=1 

TOKEN=""
TOTAL_PROCESSED=0

echo "Starting FAST BATCH TAGGING (20 resources/request) in $REGION..."
echo "Note: The script will AUTOMATICALLY STOP if it hits the API Limit."
echo "------------------------------------------------------------"

while true; do
    if [ -z "$TOKEN" ]; then
        RESPONSE=$(aws resourcegroupstaggingapi get-resources --region "$REGION" --output json)
    else
        RESPONSE=$(aws resourcegroupstaggingapi get-resources --region "$REGION" --pagination-token "$TOKEN" --output json)
    fi

    ARNS=($(echo "$RESPONSE" | jq -r '.ResourceTagMappingList[].ResourceARN'))

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
            
            # Show output ONLY if there's an error other than "empty" (e.g., invalid EKS Pods)
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

```

---

### 2. The `README.md` File

Here is the English translation for your GitHub repository:

```markdown
# 🚀 AWS Bulk Tagging Script (Super Fast + Auto-Stop)

This Bash script is used to perform mass tagging on **all AWS resources** in a specific Region using the `aws resourcegroupstaggingapi`.

It is specifically designed to handle thousands of resources by sending requests in **Batches (20 resources per request)**, and features an **Auto-Stop** mechanism that will automatically terminate the script if it detects *API Throttling / Rate Limits* from AWS.

## 🛠️ Prerequisites
Make sure you run this script in a terminal that has:
1. **AWS CLI v2** configured with appropriate permissions (minimum `TagResource` and `GetResources`, or `AdministratorAccess`).
2. **jq** installed.
*(💡 We highly recommend running this directly inside **AWS CloudShell**, as both are already pre-installed).*

## ⚙️ Configuration (How to Change Region & Tags)
Before running the script, open the `tag_all.sh` file using a text editor (e.g., `nano tag_all.sh`) and adjust the 3 variables at the top:

```bash
# ================= CONFIGURATION =================
REGION="ap-southeast-1"      # Replace with your target region code (e.g., ap-southeast-3 for Jakarta)
TAG_KEY="aws-apn-id"         # Replace with the Tag Key you want to add
TAG_VALUE="1234567890xyz"    # Replace with your Tag Value
# =================================================

```

### Common AWS Region Codes (Examples)

* `ap-southeast-1` : Singapore
* `ap-southeast-3` : Jakarta
* `ap-southeast-2` : Sydney
* `us-east-1` : N. Virginia

## 🚀 How to Run the Script

1. Give execute permissions to the script file:
```bash
chmod +x tag_all.sh

```


2. Run the script:
```bash
./tag_all.sh

```



## 🚨 Note on API Limits

If you have thousands of resources, you might encounter an error like this:

> `🚨 STOP! AWS API Limit Detected.`
> `Request limit exceeded. Account XYZ has been throttled...`

**This is completely normal!** The script stops to protect your account.
**Solution:** Just wait around **3-5 minutes** for your AWS API quota to recover, then run the `./tag_all.sh` script again. Resources that were successfully tagged previously will not be affected (it is perfectly safe to overwrite tags).

```

```
