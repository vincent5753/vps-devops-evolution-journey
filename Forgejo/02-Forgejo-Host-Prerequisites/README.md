# 02-Forgejo-Host-Prerequisites

## 這會做什麼 (What this does)
在 Stage 01 產出的通用加固 VM 上，用 `Ansible` 建立 Forgejo 執行所需的身分與目錄、以 `GPG 簽章驗證`後部署二進位檔、安裝同機 `PostgreSQL`，並套上 `systemd 沙箱`
On the hardened generic VM from Stage 01, use `Ansible` to create the identity and directories Forgejo needs, deploy the binary after `GPG signature verification`, install a co-located `PostgreSQL`, and wrap it all in a `systemd sandbox`.

這個階段結束時，Forgejo 只綁在 `127.0.0.1:3000`，網路上還連不到它。對外的代理、TLS 與 SSH 入口是 Stage 03
When this stage ends Forgejo listens on `127.0.0.1:3000` only and is not reachable from the network. The outward-facing proxy, TLS and SSH entry point are Stage 03.

### 為什麼程式碼不在這個目錄裡 (Why the code is not in this directory)
Ansible 的慣例是一整棵樹、多個 role，而 Stage 06 / 07 / 08 都會往裡面加 role。若每個階段各自帶一份 `ansible/`，你會有多份 `group_vars` 和重複的 `common_baseline`
Ansible's convention is one tree with many roles, and Stages 06 / 07 / 08 will each add more. If every stage carried its own `ansible/`, you would end up with several copies of `group_vars` and a duplicated `common_baseline`.

所以 Ansible 獨立成一棵樹放在 [`../ansible/`](../ansible/)，編號目錄只負責敘述「這個階段對那棵樹做了什麼」
So the Ansible tree lives on its own at [`../ansible/`](../ansible/), and the numbered stage directories describe what each stage did to that tree.

### 這個階段也改了 Stage 01 (This stage also changed Stage 01)
三處回頭修改，理由都寫在原檔的註解裡
Three retroactive edits, all explained in comments at the original files:

- `ubuntu-cloud_init-basic-harden.yaml` 移除了 `kernel.unprivileged_bpf_disabled = 1`。寫入 1 是單向的，重開機前無法放寬，而且**後面任何 sysctl.d 檔案都覆蓋不了它——覆寫會靜默失敗**。cloud-init 本身又是 one-shot，鎖進去等於要改就得重建 VM
  Removed `kernel.unprivileged_bpf_disabled = 1`. Writing 1 is one-way and cannot be relaxed before a reboot, and **no later sysctl.d file can override it — the write silently does nothing**. cloud-init is itself one-shot, so locking it in would mean rebuilding the VM to change it.
- `main.tf` 的 `tags` 加上 `forgejo`。Ansible 的 Proxmox inventory plugin 用 tag 分組，這個 tag 就是這台機器成為 `forgejo` 群組成員的依據
  Added `forgejo` to `tags` in `main.tf`. The Proxmox inventory plugin groups by tag, and this tag is what makes the host a member of the `forgejo` group.
- `kernel.apparmor_restrict_unprivileged_userns` 從 90- 基線移到節點角色的 `95-node-role.conf`。它是**每個節點各有其值**的參數（Forgejo 主機 `1`、階段 7 的 CI runner 要 `0` 才能跑 DinD），所以由每種節點各自宣告，基線對它保持沉默
  Moved `kernel.apparmor_restrict_unprivileged_userns` out of the 90- baseline into the node role's `95-node-role.conf`. It is a **per-node** value (Forgejo host `1`, and Stage 07's CI runner needs `0` for DinD), so each node role declares its own and the baseline says nothing about it.

  這不是安全性的改變——移走之後開機值就是 Ubuntu 24.04 的預設 `1`，跟以前一樣。改的是形狀：原本是「基線設一個值、某些節點再推翻」，現在是「基線不表態、每個節點自己宣告」，少一層互相矛盾的可能
  This changes nothing security-wise — with the line gone the boot value is Ubuntu 24.04's default of `1`, exactly as before. What changes is the shape: instead of a baseline value that some nodes overturn, every node declares its own and there is no contradiction to keep track of.

## 執行前必填 (Fill these in first)
發布政策（版本、GPG 指紋、下載來源）在 [`../ansible/group_vars/all/forgejo.yml`](../ansible/group_vars/all/forgejo.yml)，主機專屬的設定在 [`../ansible/group_vars/forgejo/main.yml`](../ansible/group_vars/forgejo/main.yml)
Release policy (version, GPG fingerprint, download source) is in [`../ansible/group_vars/all/forgejo.yml`](../ansible/group_vars/all/forgejo.yml); host-specific settings are in [`../ansible/group_vars/forgejo/main.yml`](../ansible/group_vars/forgejo/main.yml):

| 變數 / Variable | 檔案 / File | 說明 / Notes |
|---|---|---|
| `forgejo_version` | `all/forgejo.yml` | 目前是 `15.0.6`（v15 LTS 軌）。留空的話 playbook 會直接中止。換版本前先到 <https://forgejo.org/releases> 確認支援期限 / Currently `15.0.6` on the v15 LTS track. Leaving it empty aborts the playbook. Check the support window at <https://forgejo.org/releases> before changing it |
| `forgejo_static_ip` | `forgejo/main.yml` | **必須填目前這台機器已經在用的位址**，否則套用 netplan 會切斷 Ansible 自己的連線（playbook 有檢查會擋下來）/ **Must be the address the VM already holds**, otherwise applying netplan cuts Ansible's own connection (a guard task catches this) |
| `forgejo_nic` | `forgejo/main.yml` | 用 `ip -br link` 確認。**這台實測是 `eth0`，不是 Proxmox 常見的 `ens18`** —— 別照抄，重建 VM 後要重新確認 / Confirm with `ip -br link`. **Measured as `eth0` on this VM, not the `ens18` you usually see on Proxmox** — do not assume, re-check after rebuilding the VM |
| `forgejo_domain` | `forgejo/main.yml` | 純內網，預設 `git.home.arpa`（RFC 8375 保留給家用網路，不像 `.local` 會和 mDNS 衝突）/ Internal-only; defaults to `git.home.arpa` (RFC 8375 reserves it for home networks, unlike `.local` which collides with mDNS) |

還有三件在機器外面要做的事
Three more things to do outside the machine:

1. 路由器上把 `forgejo_static_ip` 從 DHCP pool 排除或設成 reservation / Reserve or exclude `forgejo_static_ip` on the DHCP server
2. 讓 `forgejo_domain` 解析得出來（路由器靜態記錄、Pi-hole 之類）/ Make `forgejo_domain` resolvable (router static record, Pi-hole, …)
3. PVE 上先拍一個快照。接下來是對一台活的機器動手 / Take a PVE snapshot first — everything below touches a live machine

密鑰與 PVE token
Secrets and the PVE token:

```bash
cd ../ansible
ansible-galaxy collection install -r requirements.yml -p collections

# 唯讀 inventory token,存進 Keychain 而不是環境變數
# The read-only inventory token, in the Keychain rather than an env var
security add-generic-password -a "$USER" -s forgejo-pve-token -w

ansible-vault create group_vars/forgejo/vault.yml   # 內容見 vault.yml.example
```

**沒有任何祕密進版控,連加密過的也不進。** `vault.yml` 與 `bin/vault-pass.sh` 都被 `.gitignore` 排除,只有對應的 `*.example` 留在版控裡;PVE token 則根本不落地成檔案,直接放 Keychain
**No secrets are committed, not even encrypted ones.** `vault.yml` and `bin/vault-pass.sh` are gitignored; only the matching `*.example` files stay in version control. The PVE token never becomes a file at all — it lives in the Keychain.

理由是 git 歷史永久保存:密文一旦推上遠端,日後就算輪替了 vault 密碼,舊版本仍留在歷史裡可離線暴力破解。也就是說 vault 密碼的強度等於保護所有歷史祕密的強度
The reason is that git history is permanent: once ciphertext is pushed, rotating the vault password later leaves the old blobs offline-crackable forever. The vault password's strength is therefore the strength protecting every historical secret.

而既然密碼從 Keychain 取、從來不需要用打的，**就沒有理由讓它可記憶**——直接用一長串隨機字元。這一點值得說破:「好記」是密碼強度最常見的隱形上限,而它在這裡根本不是需求
And since the password comes from the Keychain and is never typed, **there is no reason for it to be memorable** — use a long random string. This is worth saying out loud: memorability is the most common invisible ceiling on password strength, and here it was never a requirement at all.

代價要說清楚:**從乾淨的 clone 開始,playbook 不會自帶還原所需的一切**,`vault.yml` 必須重建或以外部管道取得。`*.example` 檔的作用就是讓「需要填什麼」仍然是自我描述的
The cost, stated plainly: **from a clean clone the playbook does not carry everything needed to restore itself** — `vault.yml` must be recreated or moved in out of band. The `*.example` files exist so that what needs filling in stays self-documenting.

建議另開一把**唯讀**的 PVE token 給 Ansible。Stage 01 那把有 `VM.Allocate` / `VM.Clone` / `VM.PowerMgmt`，而 inventory 只需要「看」
Use a separate **read-only** PVE token for Ansible. The Stage 01 token carries `VM.Allocate` / `VM.Clone` / `VM.PowerMgmt`; the inventory only needs to look. PVE's built-in `PVEAuditor` role scoped to `/vms` and `/nodes` is enough.

## 執行 (Running it)
```bash
cd ../ansible
ansible-inventory --graph                       # 先確認 forgejo 群組抓得到那台機器
ansible-playbook site.yml --vault-password-file ./bin/vault-pass.sh --check --diff
ansible-playbook site.yml --vault-password-file ./bin/vault-pass.sh
```

Vault 密碼由 `bin/vault-pass.sh` 從 macOS Keychain 取出（該檔 gitignored，範本是 `bin/vault-pass.sh.example`）。想省掉每次的旗標，就把 `ansible.cfg` 的 `vault_password_file` 取消註解；沒有 helper script 時退回 `--ask-vault-pass` 也能運作
The vault password comes from the macOS Keychain via `bin/vault-pass.sh` (gitignored; the template is `bin/vault-pass.sh.example`). To drop the flag, uncomment `vault_password_file` in `ansible.cfg`; without the helper, `--ask-vault-pass` still works.

> **⚠ 輪替密碼時的順序陷阱**
>
> `ansible-vault rekey` 之後、Keychain 更新之前，helper 回傳的是**舊**密碼而檔案已用新密碼加密。這段期間跑 playbook 會得到 `Decryption failed`，看起來像 rekey 失敗了——它沒有，只是兩邊還沒對上。更新 Keychain 記得加 `-U`，否則 `security` 會說項目已存在
> Between `ansible-vault rekey` and updating the Keychain, the helper returns the **old** password while the file is already encrypted with the new one. A playbook run in that window fails with `Decryption failed`, which looks like a failed rekey but is not. Remember `-U` when updating the Keychain, or `security` refuses because the item exists.

第一個管理員帳號**不在 playbook 裡**，因為 `forgejo admin user create` 不具冪等性。手動跑一次
The first admin account is **not in the playbook**, because `forgejo admin user create` is not idempotent. Run it once by hand:

```bash
sudo -u git /usr/local/bin/forgejo admin user create \
  --admin --username <name> --email <mail> \
  --config /etc/forgejo/app.ini
```

## 驗收 (Acceptance)

### 冪等性 (Idempotency)
連續執行三次，第二三次必須 `changed=0`
Run it three times; the second and third must report `changed=0`.

特別注意 `SECRET_KEY` 與 `INTERNAL_TOKEN`：它們在首次執行時於目標主機產生，之後每次都從 app.ini 讀回來，從不進入 vault 也不經過控制端。如果每次重新產生，playbook 會「冪等地把所有人登出」——既有的 session、access token 與 2FA 全部作廢
Watch `SECRET_KEY` and `INTERNAL_TOKEN` in particular: they are generated on the target on the first run and read back out of app.ini afterwards, never entering the vault or reaching the control node. Regenerating them each time would make the playbook "idempotently log everyone out" — invalidating every session, access token and 2FA enrolment.

### 簽章驗證確實會擋 (Signature verification actually blocks)
故意改動 binary 一個 byte，確認腳本以非零狀態碼中止，且 `/usr/local/bin/forgejo` **未被覆寫**
Flip one byte in the binary and confirm the run aborts non-zero and `/usr/local/bin/forgejo` is **not overwritten**.

順帶說明為什麼沒有比對 `.sha256`：那個檔案本身沒有被簽章，而且和 binary 放在同一個位置。能竄改 binary 的人也能改掉它。它防的是傳輸損毀，不是竄改，列進供應鏈驗證會產生虛假的安全感
Note there is deliberately no `.sha256` comparison: that file is unsigned and sits next to the binary, so anyone able to tamper with one can tamper with the other. It detects a truncated download, not tampering — listing it as a supply-chain control produces false confidence.

### 服務與沙箱 (Service and sandbox)
```bash
systemctl status forgejo
systemd-analyze security forgejo          # 參考值，不是驗收門檻 / reference only, not a gate
ss -ltnp | grep 3000                      # 必須只綁 127.0.0.1 / must be 127.0.0.1 only
ls -l /etc/forgejo/app.ini                # root:git 0640
sysctl kernel.apparmor_restrict_unprivileged_userns kernel.unprivileged_bpf_disabled
```

### 功能完整性 —— 這才是真正的門檻 (Functional integrity — this is the real gate)
安全分數高但推不了 code 是沒有意義的
A high security score with broken pushes is worth nothing.

- [x] 含 pre-receive hook 的 push / push with a pre-receive hook
- [x] 大型儲存庫推送 / large repository push
- [x] `git gc` —— **必須從管理後台的維運頁觸發**。在主機上 `sudo -u git git gc` 跑在 unit 的 namespace 外面，測不到沙箱 / **trigger it from the admin Maintenance page**; `sudo -u git git gc` on the host runs outside the unit's namespace and tests nothing
- [x] **大型 LFS 上傳，確認暫存資料全程留在 `/var/lib/forgejo` 底下、`/tmp` 沒被碰過** / **large LFS upload, confirming staging stays under `/var/lib/forgejo` and `/tmp` is never touched**

在主機上監看 / Watch on the host:

```bash
watch -n1 'ls -la /var/lib/forgejo/data/lfs/tmp/ ; df -h / ; free -m'
```

> **⚠ 監看的路徑跟直覺不同，實測後修正**
>
> 三條寫入路徑各走各的，`Environment=TMPDIR` 對其中兩條**完全沒有作用**
> Three write paths, and `Environment=TMPDIR` is irrelevant to two of them:
>
> | 動作 / Action | 暫存位置 / Staging location |
> |---|---|
> | 一般 git push | repo 自己的 `objects/pack/`（`git receive-pack` 不看 `TMPDIR`）/ the repo's own `objects/pack/` |
> | **LFS 上傳** | **`data/lfs/tmp/`,寫完 rename 進內容定址路徑** / **`data/lfs/tmp/`, renamed into the content-addressed path** |
> | web UI 檔案上傳 | `[repository.upload] TEMP_PATH`，也就是 `/var/lib/forgejo/tmp/uploads` |
>
> 實測 3 GB 上傳:`data/lfs/tmp` 與最終物件的 mtime 相同到奈秒(rename 的證據)，
> `/var/lib/forgejo/tmp` 全程是空的，`/tmp` 沒被碰過
> Measured on a 3 GB upload: `data/lfs/tmp` and the final object share an mtime to the
> nanosecond (the fingerprint of a rename), `/var/lib/forgejo/tmp` stayed empty throughout,
> and `/tmp` was never touched.
>
> 所以計畫修正 2-5 擔心的「大型 LFS 上傳吃光 `/tmp`」在這個部署上**兩層都不成立**——
> `/tmp` 不是 tmpfs,而且 LFS 根本不走 `/tmp`。`TMPDIR` 保留是零成本的縱深防禦
> (任何呼叫 `os.TempDir()` 的程式碼會落在資料磁碟上)，但它**不是**這一項驗收的對象
> So the plan's correction 2-5 — a large LFS upload exhausting `/tmp` — fails on both counts
> here: `/tmp` is not tmpfs, and LFS never goes near it. Keeping `TMPDIR` is zero-cost defence
> in depth (anything calling `os.TempDir()` lands on the data disk), but it is **not** what
> this acceptance item verifies.
>
> **真正要驗的是**:3 GB 的暫存與物件全部留在 `/var/lib/forgejo`(即 `ReadWritePaths` 之內、
> 與備份同一顆磁碟)，而不是散落到沙箱外面
> **What this actually verifies**: all 3 GB of staging and object data stays under
> `/var/lib/forgejo` — inside `ReadWritePaths`, on the same disk as the backups — rather than
> leaking outside the sandbox.

Stage 03 之前要測 LFS，得先繞過 ROOT_URL（理由見「已知的刻意取捨」）。開一條 tunnel、暫時覆寫，測完再跑一次還原
To test LFS before Stage 03 you must work around ROOT_URL (see Deliberate trade-offs). Open a tunnel, override temporarily, then re-run to restore:

```bash
ssh -L 3000:127.0.0.1:3000 opentofu_adm@<vm-ip>     # 另一個終端保持開著 / keep this open

ansible-playbook site.yml -e forgejo_root_url=http://127.0.0.1:3000/
#   … clone http://127.0.0.1:3000/<user>/<repo>.git 並推送 LFS 檔案 …
ansible-playbook site.yml                            # 還原 / restore
```

> **⚠ 這一項的理由和計畫寫的不一樣，實測後修正**
>
> 計畫修正 2-5 說「多數現代發行版的 `/tmp` 是 tmpfs，所以大型 LFS 上傳會吃光 RAM 觸發 OOM」。**在這個映像上不成立**：Ubuntu 24.04 cloud image 的 `/tmp` 就在根檔案系統上，`findmnt /tmp` 是空的，`tmp.mount` 也是 `not-found`
> The plan's correction 2-5 claims `/tmp` is tmpfs on most modern distributions, so a large LFS upload exhausts RAM and trips the OOM killer. **That does not hold on this image**: on the Ubuntu 24.04 cloud image `/tmp` lives on the root filesystem — `findmnt /tmp` returns nothing and `tmp.mount` is `not-found`.
>
> 而且 `PrivateTmp=yes` 在 systemd 255 上不是建立新的 tmpfs，它是把宿主機 `/tmp` 底下的一個私有子目錄 bind mount 進來，底層是什麼就繼承什麼
> `PrivateTmp=yes` on systemd 255 does not create a fresh tmpfs either — it bind mounts a private subdirectory of the host's `/tmp` and inherits whatever backs it.
>
> 所以真正的限制是**那顆 20 GiB 根磁碟**，不是 RAM。而 `/var/lib/forgejo` 也在同一個檔案系統上，代表這個 `TMPDIR` 重導**今天並沒有多爭取到任何容量**
> The real constraint is therefore the **20 GiB root disk**, not RAM. And since `/var/lib/forgejo` sits on that same filesystem, the `TMPDIR` redirect buys no capacity today.
>
> 保留它的理由變成兩個成本為零的:暫存資料和儲存庫、備份放在一起比較好推理；以及 `/tmp` 的發行版預設一直在往 tmpfs 移動，哪天翻過去這台機器已經不受影響。**升級發行版之後用 `findmnt /tmp` 重新確認，不要相信任何一種說法**
> It stays for two zero-cost reasons: temporary data sits beside the repositories and backups, and the distro default for `/tmp` has been drifting toward tmpfs — the day it flips, this host is already unaffected. **Re-check with `findmnt /tmp` after a release upgrade rather than trusting either story.**

`vm_memory` 已從 2048 提到 4096(`variables.tf` 預設值與 tfvars 都改了)。理由不是上面那個 OOM 情境，而是 Forgejo 和 PostgreSQL 同機共用
`vm_memory` has been raised from 2048 to 4096 (both the `variables.tf` default and the tfvars). The reason is not the OOM scenario above but Forgejo and PostgreSQL sharing one box.

若某項功能測試失敗，一次只放寬一個 unit 指令再重測。被擋掉的系統呼叫在 journal 裡是 `EPERM` 而不是啟動失敗，常見嫌疑犯是 `SystemCallFilter` 和 `RestrictNamespaces`
If a functional test fails, relax one unit directive at a time and re-test. Denied syscalls show up in the journal as `EPERM`, not as a startup failure; the usual suspects are `SystemCallFilter` and `RestrictNamespaces`.

## 已知的刻意取捨 (Deliberate trade-offs)

**`git` 帳號的 shell 是 `/bin/bash` 而不是 `nologin`。** Stage 03 的主機 OpenSSH 會透過 `AuthorizedKeysCommand` 取得帶 forced command 的金鑰項，而 sshd 是用該帳號的**登入 shell** 去執行那個 command。`nologin` 會拒絕，結果是 web UI 正常但所有 SSH clone / push 全部失敗——一種很難聯想的局部失效。這裡也不構成安全弱點：該帳號沒有密碼、沒有自己的 `authorized_keys`
The `git` account's shell is `/bin/bash`, not `nologin`. In Stage 03 the host's OpenSSH gets a key entry with a forced command from `AuthorizedKeysCommand`, and sshd runs that command through the account's **login shell**. `nologin` refuses it, so the web UI keeps working while every SSH clone and push fails — a partial failure that is hard to trace back. It is not a weakness here either: the account has no password and no `authorized_keys` of its own.

**PostgreSQL 和 Forgejo 同一台，走 TCP `127.0.0.1` 而不是 unix socket。** 分開放但不做複本，是把兩個單點串聯，可用性反而更低。走 loopback TCP 讓將來搬到獨立主機變成單一變數的改動
PostgreSQL is co-located and reached over TCP `127.0.0.1` rather than a unix socket. Separating it without also replicating it puts two single points of failure in series, which lowers availability. Loopback TCP makes a later move to its own host a one-variable change.

**`ROOT_URL` 已經寫成 `https://`，但 Stage 03 之前沒有東西提供 TLS。** ROOT_URL 會被寫進 clone URL、webhook payload 和 avatar 連結，一次設好比之後回頭改乾淨。介面上顯示的 clone URL 在 Stage 03 之前就是不能用
`ROOT_URL` is already `https://`, though nothing serves TLS until Stage 03. It is baked into clone URLs, webhook payloads and avatar links, so setting it once beats rewriting them later. The clone URL shown in the UI simply does not work yet.

**代價比上面那句大：LFS 在 Stage 03 之前也是壞的。** LFS 的 batch API 回傳的是**由 ROOT_URL 組出的絕對網址**，client 拿到 `https://git.home.arpa/...` 就會去連 443；那裡還沒有人在聽，於是 batch 一直回 200、實際上傳的 PUT 永遠到不了，畫面卡在 `Uploading LFS objects: 0%`。這不是沙箱問題，日誌裡看不到任何錯誤。要在本機測 LFS，暫時覆寫 `forgejo_root_url` 即可（見下方驗收章節）
The cost is larger than that line suggests: **LFS is also broken until Stage 03.** The LFS batch API returns **absolute URLs built from ROOT_URL**, so the client is told to PUT to `https://git.home.arpa/...` and dials port 443, where nothing is listening yet. The batch call keeps returning 200 while the upload never arrives, and the push sits at `Uploading LFS objects: 0%`. This is not a sandbox problem and produces no error in the log. To test LFS locally, override `forgejo_root_url` temporarily (see Acceptance).

**`common_baseline` role 管理的是 cloud-init 寫的同一個檔案。** cloud-init 在 Ansible 連得上之前就先加固機器，這個 role 則是同一組值的持續強制。新機器上是 no-op，被手動改過的機器會被修回來。兩邊重複是可以的，**因為值一模一樣**；真正的反模式是兩個真相來源給出不同的值——所以改一邊就要改另一邊
The `common_baseline` role manages the same file cloud-init writes. cloud-init hardens the machine before Ansible can reach it; the role is continuous enforcement of the same values. It is a no-op on a fresh VM and repairs drift on a hand-edited one. The duplication is fine **because the values are identical** — the anti-pattern would be two sources of truth that disagree, so changing one means changing the other.

## 路徑標示 (Path marker)
本階段屬於**路徑 A（裸機 + systemd + 主機 OpenSSH + 主機 PostgreSQL）**
This stage belongs to **path A (bare metal + systemd + host OpenSSH + host PostgreSQL)**.

這份 systemd unit 會在 Stage 08 被 Pod `securityContext` 完整取代。這不是浪費——兩種隔離模型都做過一遍是有價值的——但值得先知道，才不會在這裡把沙箱調到完美
This systemd unit is replaced wholesale by a Pod `securityContext` in Stage 08. That is not waste — working through both isolation models is the point — but knowing it up front stops you polishing the sandbox forever here.
