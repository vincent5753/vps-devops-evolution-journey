# Stage 3: generate the self-signed root CA for the homelab. Run once, on
# a Windows Ansible control node. Mirrors 00-generate-ca.sh — see that file
# for the reasoning behind each step. Not idempotent by re-running: it
# refuses to overwrite an existing CA, because rotating the root means
# redistributing trust to the VM, the Mac, and (later) the Stage 7 runner.

$ErrorActionPreference = "Stop"

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$AnsibleDir = Resolve-Path (Join-Path $ScriptDir "..\ansible")
$PkiDir     = Join-Path $AnsibleDir "pki"
$CaKey      = Join-Path $PkiDir "ca.key"
$CaCert     = Join-Path $PkiDir "ca.pem"
$CaPassScript = Join-Path $AnsibleDir "bin\ca-pass.ps1"
$CaSubject  = "/CN=Forgejo Homelab Root CA"
$CaDays     = 3650

Write-Host "=== 3-1. Preflight ==="

$opensslVersion = & openssl version
if ($opensslVersion -notmatch "^OpenSSL 3\.") {
    Write-Error "Refusing to run: 'openssl version' reports '$opensslVersion', not OpenSSL 3.x. Install OpenSSL 3.x and ensure it is first on PATH."
    exit 1
}

if (-not (Test-Path $CaPassScript)) {
    Write-Error "Missing: $CaPassScript`nCopy bin/ca-pass.ps1.example to bin/ca-pass.ps1 and store the CA passphrase in Windows Credential Manager first."
    exit 1
}

New-Item -ItemType Directory -Force -Path $PkiDir | Out-Null

if ((Test-Path $CaKey) -or (Test-Path $CaCert)) {
    Write-Error "Refusing to overwrite an existing CA ($CaKey / $CaCert). Delete both by hand first if a genuine rotation is intended."
    exit 1
}

Write-Host "=== 3-2. Generate the CA private key (RSA 4096, AES-256 encrypted) ==="
& $CaPassScript | & openssl genpkey `
    -algorithm RSA `
    -pkeyopt rsa_keygen_bits:4096 `
    -aes256 -pass stdin `
    -out $CaKey

Write-Host "=== 3-3. Self-sign the CA certificate ($CaDays days) ==="
& $CaPassScript | & openssl req -x509 -new `
    -key $CaKey -passin stdin `
    -sha256 -days $CaDays `
    -subj $CaSubject `
    -addext "basicConstraints=critical,CA:TRUE,pathlen:0" `
    -addext "keyUsage=critical,keyCertSign,cRLSign" `
    -out $CaCert

Write-Host ""
Write-Host "=== Done ==="
& openssl x509 -in $CaCert -noout -subject -dates
Write-Host ""
Write-Host "$CaCert is meant to be committed (it is the trust anchor)."
Write-Host "$CaKey is gitignored — verify with: git check-ignore -v `"$CaKey`""
Write-Host "Next: 01-issue-leaf-cert.ps1 to issue the git.home.arpa server certificate."
