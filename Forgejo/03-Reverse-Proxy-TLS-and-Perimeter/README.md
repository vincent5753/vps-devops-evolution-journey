# 03-Reverse-Proxy-TLS-and-Perimeter

## 這會做什麼 (What this does)
終止 TLS、建構 Git SSH 存取路徑，並在對外暴露的同一時刻套上預設拒絕防火牆。拆成三條工作線：自簽 CA → nginx + ufw → Git SSH 入口，**全部完成**
Terminate TLS, build the Git SSH access path, and apply a default-deny firewall at the moment the host becomes reachable. Split into three work lines: self-signed CA → nginx + ufw → Git SSH entry point — **all complete**.

## 工作線 1：自簽 CA 與 TLS 信任鏈 (Work line 1: self-signed CA and TLS trust chain)

### 為什麼是這個形狀 (Why this shape)
CA 私鑰很少用、外洩影響的是整條信任鏈，所以效期長（10 年）且加密存放，密碼走 macOS Keychain（或 Windows Credential Manager），比照 `ansible/bin/vault-pass.sh` 的模式，密碼從來不落地、也不用手動輸入
The CA private key is rarely used and a leak compromises the entire trust chain, so it lives long (10 years) and encrypted at rest, with the passphrase in macOS Keychain (or Windows Credential Manager) — the same pattern as `ansible/bin/vault-pass.sh`. The passphrase never touches disk and is never typed by hand.

Leaf（`git.home.arpa` 的伺服器憑證）效期刻意選短（90 天）：簽十年的憑證會讓「到期監控」變成一個十年不會響一次的假告警,練習不到任何東西；效期短才會逼出真正的續期與監控。Leaf 私鑰**不**加密，因為 nginx 要在開機時無人值守讀取它,保護全靠檔案權限
The leaf certificate (`git.home.arpa`'s server certificate) deliberately lives short (90 days): a ten-year certificate would make expiry monitoring a decade-dormant fake alert that never actually gets exercised — a short lifetime is what forces real renewal and real monitoring to happen. The leaf private key is **not** encrypted, because nginx has to read it unattended at boot; file permissions are its only protection.

### 執行前必填 (Fill this in first)
在 macOS Keychain 存一次 CA 私鑰的加密密碼(只做一次):
Store the CA private key's encryption passphrase in Keychain once:

```bash
security add-generic-password -a "$USER" -s forgejo-ca-passphrase -w
```

再把 `ca-pass.sh.example` 複製成 `ca-pass.sh`(已經做過,見 `ansible/bin/ca-pass.sh`)
Then copy `ca-pass.sh.example` to `ca-pass.sh` (already done — see `ansible/bin/ca-pass.sh`).

Windows 控制端改用 `ansible/bin/ca-pass.ps1.example`,存法見檔案內註解
On a Windows control node, use `ansible/bin/ca-pass.ps1.example` instead — see the comments inside for how to store it.

### 執行順序 (Execution order)

```bash
cd Forgejo/03-Reverse-Proxy-TLS-and-Perimeter

# 只做一次:產生 root CA(加密私鑰 + 10 年公開憑證)
# Once only: generate the root CA (encrypted key + 10-year public cert)
./00-generate-ca.sh

# 每 90 天重跑一次:簽發/續發 git.home.arpa 的伺服器憑證
# Rerun every 90 days: issue/renew the git.home.arpa server certificate
./01-issue-leaf-cert.sh

# 推送 CA 信任 + leaf 憑證到 VM
# Push CA trust + the leaf certificate to the VM
cd ../ansible
./bin/arun ansible-playbook site.yml

# 讓這台 Mac 信任這個 CA —— 使用者自己執行,不代勞
# Trust this CA on this Mac — run this yourself, it is not automated
cd ../03-Reverse-Proxy-TLS-and-Perimeter
./02-trust-ca-macos.sh
```

Windows 版腳本是 `00-generate-ca.ps1` / `01-issue-leaf-cert.ps1`,邏輯與 bash 版一致
The Windows scripts are `00-generate-ca.ps1` / `01-issue-leaf-cert.ps1`, logic identical to the bash versions.

### 產出與去留 (What gets produced, and where it lives)

| 檔案 / File | 內容 / Contents | 進版控? / Tracked? |
|---|---|---|
| `ansible/pki/ca.pem` | Root CA 公開憑證 / Root CA public certificate | **是,刻意** —— `.gitignore` 早就放行 `*.pem`,信任錨點就是靠 clone 這個 repo 來分發 / **Yes, deliberately** — `.gitignore` already allows `*.pem`; cloning the repo is how the trust anchor gets distributed |
| `ansible/pki/ca.key` | Root CA 私鑰(AES-256 加密) / Root CA private key (AES-256 encrypted) | 否,`*.key` 規則擋掉 / No, caught by the `*.key` rule |
| `ansible/pki/leaf/` | Leaf 私鑰 + 憑證,每 90 天換 / Leaf key + certificate, rotates every 90 days | 否,整個目錄 ignore / No, the whole directory is ignored |
| `ansible/bin/ca-pass.sh` | Keychain 查詢腳本(不含密碼本身) / Keychain lookup script (does not contain the passphrase itself) | 否,只有 `.example` 進版控 / No, only the `.example` is tracked |

VM 上的落地路徑(由 `roles/host_tls` 部署):
Where it lands on the VM (deployed by `roles/host_tls`):

| 路徑 / Path | 內容 / Contents | 權限 / Mode |
|---|---|---|
| `/usr/local/share/ca-certificates/forgejo-homelab-ca.crt` | CA 公開憑證,`update-ca-certificates` 會讀 / CA public cert, read by `update-ca-certificates` | `root:root 0644` |
| `/etc/ssl/forgejo/git.home.arpa.key` | Leaf 私鑰 / Leaf private key | `root:root 0600` |
| `/etc/ssl/forgejo/git.home.arpa.pem` | Leaf 憑證 / Leaf certificate | `root:root 0644` |

`/etc/ssl/forgejo/` 是專屬目錄,刻意不跟套件管理的 `/etc/ssl/certs` 混在一起。工作線 2(nginx)會直接指到這兩個檔案
`/etc/ssl/forgejo/` is a dedicated directory, deliberately kept separate from the package-managed `/etc/ssl/certs`. Work line 2 (nginx) will point straight at these two files.

## 驗收清單 (Acceptance checklist)

- [ ] `openssl x509 -in ansible/pki/ca.pem -noout -text` 顯示 `CA:TRUE`、效期約 10 年 / shows `CA:TRUE`, ~10-year validity
- [ ] `openssl verify -CAfile ansible/pki/ca.pem ansible/pki/leaf/git.home.arpa.pem` 通過 / passes
- [ ] `openssl x509 -in ansible/pki/leaf/git.home.arpa.pem -noout -ext subjectAltName -dates` SAN 是 `DNS:git.home.arpa`、效期 90 天 / SAN is `DNS:git.home.arpa`, 90-day validity
- [ ] VM 上 `/etc/ssl/forgejo/` 權限正確 / correct permissions on the VM
- [ ] VM 上 `openssl x509 -in /usr/local/share/ca-certificates/forgejo-homelab-ca.crt -noout -subject` 確認是我們的 CA / confirms it is our CA
- [ ] `./bin/arun ansible-playbook site.yml` 連跑兩次,第二次 `host_tls` 相關 task 全部 `changed=0` / two consecutive runs, second one reports `changed=0` for all `host_tls` tasks
- [ ] `security find-certificate -c "Forgejo Homelab Root CA" -p login.keychain-db` 在 Mac 上找得到(執行 `02-trust-ca-macos.sh` 之後) / found on the Mac (after running `02-trust-ca-macos.sh`)

## 工作線 2：nginx 反向代理 + ufw (Work line 2: nginx reverse proxy + ufw)

### 為什麼是這個形狀 (Why this shape)
`ufw` 從 Stage 01 cloud-init 設一次沒人管,升級成 Ansible 持續強制——跟 `common_baseline` 對 sysctl 的做法同一個邏輯。Port 80 開著只做 301 導向到 443(不是關閉),因為沒有 ACME 需求但保留使用者體驗;`client_max_body_size` 設 `4G`(不是 0 無限制),留一個防禦性上限。CSP 先跑 `Content-Security-Policy-Report-Only`,收緊留給之後。
`ufw` moves from "cloud-init set it once" to "Ansible enforces it continuously" — the same relationship `common_baseline` already has with sysctl. Port 80 stays open purely for a 301 redirect to 443 (not closed) since there's no ACME need but redirecting is nicer UX; `client_max_body_size` is `4G` (not unlimited) as a defensive cap. CSP starts as `Content-Security-Policy-Report-Only`; tightening it is future work.

### 產出 (What's deployed)
`roles/host_firewall`(ufw:22/80/443/2222 allow,預設 deny incoming)、`roles/reverse_proxy`(nginx,server block 在 `/etc/nginx/sites-available/git.home.arpa.conf`,反代到 `127.0.0.1:3000`,共用 proxy 參數在 `snippets/forgejo-proxy-params.conf`)。

### 驗收結果 (Verified)
- `nginx -t` 通過
- HTTP → HTTPS 301 導向正常
- HTTPS 回 200,`HTTP/2`,`Strict-Transport-Security`/`Content-Security-Policy-Report-Only` 兩個標頭都在
- **信任代理鏈路**:從 Mac 打進去,Forgejo 日誌記到 Mac 的真實區網位址,不是 `127.0.0.1`——證明 `X-Forwarded-For` → `REVERSE_PROXY_TRUSTED_PROXIES` 整條路徑通了
- Ansible 冪等性:連跑兩次,第二次 `changed=0`

實作時修正了計畫的一個技術細節:`template` 模組的 `validate: nginx -t -c %s` 對單一 server block 檔案不適用(會被當成整份 `nginx.conf` 驗證,缺 `http{}`/`events{}` 必判失敗)。改成部署完三個檔案後單獨跑一個 `nginx -t` task,失敗就中止、不執行 reload。

## 工作線 3:Git SSH 入口(`AuthorizedKeysCommand`) (Work line 3: Git SSH entry point)

### 一個容易忽略的技術細節 (An easy-to-miss technical detail)
這台 VM 的 sshd 是 **systemd socket-activation** 管理的(`ssh.socket`),不是傳統模式——`sshd_config` 的 `Port` 指令完全不生效,實際監聽的埠由 `ssh.socket` 的 `[Socket] ListenStream=` 決定。要開 2222 必須動 systemd,不能只改 `sshd_config`。做法是**systemd override**(`/etc/systemd/system/ssh.socket.d/20-forgejo-git-port.conf`),不是直接改 vendor unit(`/usr/lib/systemd/system/ssh.socket`)——這樣 `apt upgrade openssh-server` 不會衝突。
This VM's sshd is managed by **systemd socket activation** (`ssh.socket`), not the traditional model — the `Port` directive in `sshd_config` has no effect at all; the actual listening ports come from `ssh.socket`'s `[Socket] ListenStream=`. Opening 2222 required touching systemd, not just `sshd_config`. Done via a **systemd override** (`/etc/systemd/system/ssh.socket.d/20-forgejo-git-port.conf`), never editing the vendor unit — so an `apt upgrade openssh-server` won't conflict with it.

### 產出 (What's deployed)
`roles/git_ssh`:wrapper script `/usr/local/bin/forgejo-authorized-keys`(root:root 0755)、`sshd_config.d/60-forgejo-git.conf`(`Match User git` 區塊,含 `AuthorizedKeysFile /dev/null` 防呆)、`ssh.socket.d` override(加開 2222)。

### 驗收結果 (Verified,含實際 clone 測試)
- 重啟 `ssh.socket`/`ssh.service` 期間,獨立於 Ansible 之外的背景監測(每秒戳一次 port 22,共 40 次)**全部 UP,零斷線**——`KillMode=process` 的理論被實測證實
- `sshd -t` 通過;`ss -tlnp` 確認同一個 sshd process 同時監聽 22 與 2222
- `ufw status`:2222/tcp ALLOW
- 用一把新產生的測試金鑰:加入帳號 → `git clone ssh://git@git.home.arpa:2222/...` 成功
- **關鍵撤銷測試**:API 刪除該金鑰後,**立刻**再 clone → `Permission denied (publickey)`,exit 128——證明 `AuthorizedKeysFile /dev/null` 真的擋掉了「兩套金鑰來源並存、撤銷只有一條路徑生效」的靜默失效風險
- Ansible 冪等性:連跑兩次,第二次 `changed=0`

測試用的 repo、金鑰、兩個窄範圍 API token 已經清乾淨(repo 與金鑰用 API 刪除;兩個 token 因為 Forgejo 限制「刪 token 要真密碼、不能用 token 本身認證」,還留著,範圍僅 `write:user`/`write:repository`,建議之後在 Settings → Applications 手動撤銷)。

Stage 03 三條工作線全部完成。做完後照 HANDOFF §5.0 的教訓重開機驗證一次——改過 systemd unit 與網路服務,開機前測的都不算數。
