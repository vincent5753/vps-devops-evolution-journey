# Forgejo
## 部署階段說明 / Intro of deployment stages
01. PVE 基礎設施與 VM 供裝 (PVE infra and VM provisioning)

## 01-PVE-Infra-and-VM-Provisioning
### 這會做什麼 (What this does)
使用 `OpenTofu` 於自架的 `Proxmox VE` 上 `從範本完整複製 VM`、`擴充磁碟`、`掛載 cloud-init snippet`，並使用 `Cloud-init` 套用 `作業系統加固基線`  
Use `OpenTofu` to `full-clone a VM from a template`, `resize the disk`, and `attach a cloud-init snippet` on a self-hosted `Proxmox VE`, while using `Cloud-init` to apply an `OS hardening baseline`.

VM 基本加固包含：專用管理帳號（僅金鑰登入、停用 root）、fail2ban、ufw 預設拒絕入站、以及核心參數強化  
The VM hardening baseline includes: a dedicated admin account (key-only login, root disabled), fail2ban, ufw with default-deny inbound, and kernel parameter hardening.

### 檔案說明 (Explaining what each file does)
這裡我使用 OpenTofu 而不是 Terraform 主要是因為 Hashicorp 將 Terraform 轉為閉原授權  
I'm using OpenTofu here instead of Terraform primarily because HashiCorp shifted Terraform to a closed-source license.

`00-pve-setup.sh` 用於 PVE 節點的前置作業，在節點上以 root 執行，從頭到尾只需要跑這一次。它會建立權限收斂的 `OpenTofu` 角色與 API 使用者、下載 Ubuntu 24.04 cloud image、建立 VMID 9000 的範本，最後產生 API token  
`00-pve-setup.sh` handles the PVE node prerequisites. Run it as root on the node — only once. It creates a least-privilege `OpenTofu` role and API user, downloads the Ubuntu 24.04 cloud image, builds a template at VMID 9000, and finally generates an API token.
需要注意的是 token 的 value **只會顯示這一次**，請立刻複製，另外 ACL 是掛在 `/vms`、`/storage/*`、`/nodes`、`/sdn` 而不是掛在 `/` 上  
Important: the token value is **shown only once**, so copy it immediately. Also note the ACLs are scoped to `/vms`, `/storage/*`, `/nodes` and `/sdn` rather than being granted at `/`.

`ubuntu-cloud_init-basic-harden.yaml` 是實際做加固的地方，需要放到 PVE 節點的 `/var/lib/vz/snippets/` 下並設為 `644 root:root`  
`ubuntu-cloud_init-basic-harden.yaml` is where the actual hardening happens. Place it under `/var/lib/vz/snippets/` on the PVE node with `644 root:root`.
**使用前務必把 `ssh_authorized_keys` 換成你自己的公鑰**，否則你會建出一台登不進去的機器  
**Replace `ssh_authorized_keys` with your own public keys before using it**, otherwise you will end up with a VM you cannot log into.

`provider.tf` 宣告 `bpg/proxmox` provider。這裡刻意不設定 `ssh {}` 區塊，因為 snippet 是手動放在節點上的，不需要 provider 幫忙上傳，也就不必給它 SSH 權限  
`provider.tf` declares the `bpg/proxmox` provider. The `ssh {}` block is intentionally left out — the snippet is placed on the node manually, so the provider never needs to upload anything, and therefore never needs SSH access.

`main.tf` 從範本完整複製（full clone）出 VM、把範本的 3584M 磁碟擴充到指定大小、掛上 cloud-init snippet 並以 DHCP 取得 IP  
`main.tf` full-clones the VM from the template, grows the template's 3584M disk to the requested size, attaches the cloud-init snippet, and gets an IP via DHCP.
兩點需要注意：磁碟**只能放大不能縮小**，縮小會直接報錯；而一旦指定了 `user_data_file_id`，PVE 自動產生的 user-data 會被完全取代，使用者、SSH 金鑰、hostname 都要靠 yaml 自己處理  
Two caveats: the disk can **only grow, never shrink** — shrinking errors out. And once `user_data_file_id` is set, it fully replaces the user-data PVE would generate, so users, SSH keys and hostname all have to be handled by the yaml itself.

`variables.tf` 和 `outputs.tf` 分別是變數定義與輸出。`vm_ipv4` 需要 `qemu-guest-agent` 就緒後才讀得到，剛 apply 完可能是空的  
`variables.tf` and `outputs.tf` hold the variable definitions and outputs. `vm_ipv4` only becomes readable once `qemu-guest-agent` is up, so it may be empty right after apply.
`agent_timeout` 預設放寬到 `20m`，因為 cloud-init 會做 `apt upgrade` 再重開機，家用頻寬下預設的 15m 常常不夠，等不到 IP 會被誤判為失敗  
`agent_timeout` is relaxed to `20m` by default, because cloud-init runs `apt upgrade` and then reboots — on home bandwidth the default 15m often isn't enough, and timing out while waiting for an IP gets misread as a failure.

記得把 `terraform.tfvars.example` 重新命名為 `terraform.tfvars` 並填入你自己的 `pve_endpoint` 與 `pve_api_token`  
Remember to rename `terraform.tfvars.example` to `terraform.tfvars` and fill in your own `pve_endpoint` and `pve_api_token`.

### 快速驗證 / A quick verification
部署完之後記得把 IP 換成 `tofu output` 給你的那個  
Once deployed, remember to swap in the IP that `tofu output` gave you.
```
echo "===== VM 資訊 / VM info =====" && \
tofu output && \
echo "" && \
echo "===== cloud-init 是否跑完 / Is cloud-init done =====" && \
ssh opentofu_adm@<vm-ip> 'cloud-init status' && \
echo "" && \
echo "===== 核心參數是否生效 / Are the kernel params applied =====" && \
ssh opentofu_adm@<vm-ip> 'sysctl \
  kernel.kptr_restrict \
  kernel.dmesg_restrict \
  kernel.unprivileged_bpf_disabled \
  kernel.apparmor_restrict_unprivileged_userns \
  net.ipv4.tcp_syncookies \
  kernel.randomize_va_space' && \
echo "" && \
echo "===== 防火牆 / Firewall =====" && \
ssh opentofu_adm@<vm-ip> 'sudo ufw status verbose'
```
`cloud-init status` 要看到 `status: done` 才算完成。因為 yaml 最後會觸發重開機，太早連進去會看到 `System is going down`，等一下再試就好  
You want `cloud-init status` to report `status: done`. The yaml triggers a reboot at the end, so connecting too early shows `System is going down` — just wait a moment and retry.
