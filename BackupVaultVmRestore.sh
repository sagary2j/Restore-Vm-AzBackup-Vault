#!/bin/sh

az account set --subscription 'subscription-id'

RG="RG-name"
vault="dev-vault"
Target_RG="Test-Restore-VM"
storage_account="testrestorevm4backup"

container_name=$(az backup container list --resource-group $RG --vault-name $vault --backup-management-type AzureIaasVM  --query '[].name' -o tsv)
echo "Container Name: $container_name"

item_name=$(az backup item list -g $RG -v $vault --query '[].properties.friendlyName' -o tsv)
echo "Item Name: $item_name"

recoverypoint=$(az backup recoverypoint list -g $RG -v $vault --container-name "$container_name" --item-name $item_name --query '[0].name' -o tsv)

echo "Latest Recovery Point: $recoverypoint"

az backup restore restore-disks --container-name "$container_name" --item-name "$item_name" --resource-group $RG --rp-name "$recoverypoint" --storage-account $storage_account --vault-name $vault --target-resource-group $Target_RG

sleep 200s;

## Monitor the restore job

# To get the job ID:
job_id=$(az backup job list --resource-group $RG --vault-name $vault --query '[0].name' -o tsv)
url="$(az backup job show -v $vault -g $RG -n $job_id --query properties.extendedInfo.propertyBag -o yaml | awk -F": " ' { print $2 }' | tail -1)"
template_name=$(basename $url)
cname="$(az backup job show -v $vault -g $RG -n $job_id --query properties.extendedInfo.propertyBag -o yaml | awk -F": " ' { print $2 }' | head -1)"

expiretime=$(date -u -d '30 minutes' +%Y-%m-%dT%H:%MZ)
connection=$(az storage account show-connection-string \
    --resource-group $RG \
    --name $storage_account \
    --query connectionString)

#echo "Connection: $connection"

token=$(az storage blob generate-sas \
    --container-name $cname \
    --name $template_name \
    --expiry $expiretime \
    --permissions r \
    --output tsv \
    --connection-string $connection)

#echo "Token: $token"

url=$(az storage blob url \
    --container-name $cname \
    --name $template_name \
    --output tsv \
    --connection-string $connection)

#echo "URL: $url"
 
az deployment group create  --name VmRestore --resource-group $Target_RG --parameters '{ "VirtualMachineName": {"value":"restore-vm"}}'  --template-uri $url?$token

az vm list --resource-group $Target_RG --output table
