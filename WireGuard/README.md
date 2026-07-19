# WireGuard
## 部署方式說明 / Intro of how to deploy
01. 人工點擊 (Click manually on Web UI)
02. 基礎設施即代碼 (Infra as Code)

## 01 人工點擊 (Click manually on Web UI)
TBA

## 02 基礎設施即代碼 (Infra as Code)
### 這會做什麼 (What this does)
使用 `OpenTofu` 於 GCP 上 `建立 VM`、`新增 WireGuard 防火牆規則`、`申請靜態IP`，並使用 `Cloud-init` 自動安裝 `WireGuard`  
Use `OpenTofu` to `provision a VM`, `add firewall rule for WireGuard`, and `request a static IP on GCP`, while using `Cloud-init` to automatically install WireGuard.

### 檔案說明 (Explaining what each file does)
這裡我使用 OpenTofu 而不是 Terraform 主要是因為 Hashicorp 將 Terraform 轉為閉原授權，相關檔案位於 `OpenTofu/` 下  
I'm using OpenTofu here instead of Terraform primarily because HashiCorp shifted Terraform to a closed-source license. The related files are located at the `OpenTofu/` folder.

`OpenTofu/01-install-gcloud.sh` 和 `OpenTofu/02-setup-gcloud.sh` 用於設定 gcloud 相關環境，你會需要把 `PROJECT_ID='__your_project_id__'` 和 `ACCOUNT='__your_user_account__'` 改為你自己的資訊  
`OpenTofu/01-install-gcloud.sh` and `OpenTofu/02-setup-gcloud.sh` are used to configure the gcloud environment. You will need to modify PROJECT_ID='__your_project_id__' and ACCOUNT='__your_user_account__' with your own info.
這裡會需要特別注意，你會需要有綁定 Billing Account 才能啟用 Compute API  
Important Note: You will need to link a Billing Account to your project in order to enable the Compute Engine API.

`OpenTofu/03-install-opentofu.sh` 用於安裝 `OpenTofu`，基本上無腦跑就好了  
`OpenTofu/03-install-opentofu.sh` is used to install OpenTofu, you can just run it directly without any extra configuration.

`OpenTofu/04-run-opentofu.sh` 用於實際部署環境，需要注意的是我把實際部署和清理環境的 `tofu apply` 和 `tofu destroy` 註解掉了，所以你只會看到 `OpenTofu` 預覽的 `tofu plan`  
`OpenTofu/04-run-opentofu.sh` is used to deploy the environment using `OpenTofu`. Note that I have commented out `tofu apply` and `tofu destroy` (which handle the actual deployment and cleanup), so you will only see the `tofu plan` preview.  
需要注意記得把 `terraform.tfvars.example` 重新命名為 `terraform.tfvars` 並修改為你自己要使用的 `project_id`  
Please ensure that you renamed `terraform.tfvars.example` to `terraform.tfvars` and modify the `project_id` to match your specific project.

### 快速驗證 / A quick verification
如果你和我一樣懶的話，直接這樣跑就好了  
If you are lazy like me, just run the following commands
```
echo "===== 靜態 IP / Static IP =====" && \
gcloud compute addresses list \
  --format="table(name,address,region.basename(),networkTier,status)" && \
echo "" && \
echo "===== VM 資訊 / VM info=====" && \
gcloud compute instances list \
  --format="table(name,zone.basename(),machineType.basename(),status,networkInterfaces[0].accessConfigs[0].natIP:label=EXTERNAL_IP)" && \
echo "" && \
echo "===== VM 介面和 Network Tier / VM interface and Network Tier =====" && \
gcloud compute instances describe wireguard-002 --zone=us-west1-b \
  --format="table(networkInterfaces[0].accessConfigs[0].networkTier:label=VM_TIER,networkInterfaces[0].accessConfigs[0].natIP:label=VM_NAT_IP)" && \
echo "" && \
echo "===== 防火牆 / Firewall =====" && \
gcloud compute firewall-rules list --filter="name=allow-wireguard-002" \
  --format="table(name,direction,priority,allowed[].map().firewall_rule().list():label=ALLOW,sourceRanges.list():label=SRC_RANGES)"
```