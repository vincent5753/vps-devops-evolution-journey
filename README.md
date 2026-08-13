# vps-devops-evolution-journey

自學 DevOps 的實作紀錄。每個目錄是一個獨立的題目，寫的是「為什麼這樣做」而不只是「做了什麼」——包含走錯的路和推翻掉的假設
A self-taught DevOps logbook. Each directory is a self-contained topic, and the writing is about *why* rather than only *what* — including the wrong turns and the assumptions that got overturned.

## WireGuard
介紹我如何部署 WireGuard  
Telling you how I deploy the WireGuard.

## [Forgejo](Forgejo/)
自架 Git 平台的分階段演進：從 VM 供裝一路做到 Kubernetes。**刻意走過三條互斥的部署路徑**（裸機 systemd → 容器 → Kubernetes），因為每一條要處理的問題都不同，走完三條學到的比只走一條多
A staged build-out of a self-hosted Git platform, from VM provisioning through to Kubernetes. It deliberately walks **three mutually exclusive deployment paths** (bare-metal systemd → containers → Kubernetes), because each one raises different problems and doing all three teaches more than doing one.

| 階段 / Stage | 內容 / Contents | 狀態 / Status |
|---|---|---|
| [01](Forgejo/01-PVE-Infra-and-VM-Provisioning/) | OpenTofu 在 Proxmox 上供裝 VM，cloud-init 做通用加固基線 / OpenTofu provisioning on Proxmox, cloud-init hardening baseline | ✅ |
| [02](Forgejo/02-Forgejo-Host-Prerequisites/) | Ansible 建立服務身分與目錄、GPG 驗簽部署二進位檔、同機 PostgreSQL、systemd 沙箱 / Ansible identity and directories, GPG-verified binary, co-located PostgreSQL, systemd sandbox | ✅ |
| 03–12 | L7 代理與 TLS、備份還原演練、容器化、IaC、CI/CD 自舉、Kubernetes、GitOps、可觀測性、災難復原 / TLS termination, backup drills, containers, IaC, CI/CD, Kubernetes, GitOps, observability, DR | 規劃中 / planned |

Ansible 的程式碼集中在 [`Forgejo/ansible/`](Forgejo/ansible/) 而不是分散在各階段目錄——它是一整棵樹、多個 role，後面的階段會繼續往裡面加
The Ansible code lives together in [`Forgejo/ansible/`](Forgejo/ansible/) rather than being split across stage directories: it is one tree with many roles, and later stages keep adding to it.

> **祕密一律不進版控，連加密過的也不進。** git 歷史是永久的——密文一旦推上遠端，日後就算輪替密碼，舊版本仍留在歷史裡可離線暴力破解。所以 repo 裡只有 `*.example`，真正的值靠 ansible-vault 與 Keychain
> **No secrets are committed, not even encrypted ones.** Git history is permanent: once ciphertext is pushed, rotating the password later leaves the old blobs offline-crackable forever. The repo carries only `*.example` files; the real values live in ansible-vault and the Keychain.
