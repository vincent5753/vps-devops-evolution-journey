# Stage 3: issue (or renew) the git.home.arpa server certificate, signed by
# the CA from 00-generate-ca.ps1. Mirrors 01-issue-leaf-cert.sh — see that
# file for the reasoning behind each step. Safe to re-run: this is the
# 90-day-cycle script, unlike the CA generator.

$ErrorActionPreference = "Stop"

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$AnsibleDir = Resolve-Path (Join-Path $ScriptDir "..\ansible")
$PkiDir     = Join-Path $AnsibleDir "pki"
$LeafDir    = Join-Path $PkiDir "leaf"
$CaKey      = Join-Path $PkiDir "ca.key"
$CaCert     = Join-Path $PkiDir "ca.pem"
$CaPassScript = Join-Path $AnsibleDir "bin\ca-pass.ps1"

# Mirrors group_vars/forgejo/main.yml: forgejo_domain.
$Domain   = "git.home.arpa"
$LeafKey  = Join-Path $LeafDir "$Domain.key"
$LeafCert = Join-Path $LeafDir "$Domain.pem"
$LeafDays = 90

Write-Host "=== 3-1. Preflight ==="

$opensslVersion = & openssl version
if ($opensslVersion -notmatch "^OpenSSL 3\.") {
    Write-Error "Refusing to run: 'openssl version' reports '$opensslVersion', not OpenSSL 3.x."
    exit 1
}

foreach ($f in @($CaKey, $CaCert)) {
    if (-not (Test-Path $f)) {
        Write-Error "Missing $f — run 00-generate-ca.ps1 first."
        exit 1
    }
}

if (-not (Test-Path $CaPassScript)) {
    Write-Error "Missing: $CaPassScript"
    exit 1
}

New-Item -ItemType Directory -Force -Path $LeafDir | Out-Null

if (Test-Path $LeafCert) {
    Write-Host "Existing leaf certificate found, expiry:"
    & openssl x509 -in $LeafCert -noout -enddate
    Write-Host "Proceeding to issue a fresh one (this overwrites it)."
}

$CsrFile = New-TemporaryFile

try {
    Write-Host "=== 3-2. Generate the leaf private key (RSA 2048, unencrypted) ==="
    & openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out $LeafKey

    Write-Host "=== 3-3. Generate the CSR ==="
    & openssl req -new -key $LeafKey -subj "/CN=$Domain" -out $CsrFile.FullName

    Write-Host "=== 3-4. Sign with the CA ($LeafDays days) ==="
    $extfile = New-TemporaryFile
    "subjectAltName=DNS:$Domain`nbasicConstraints=CA:FALSE`nkeyUsage=digitalSignature,keyEncipherment`nextendedKeyUsage=serverAuth`n" | Set-Content -NoNewline $extfile.FullName
    & $CaPassScript | & openssl x509 -req `
        -in $CsrFile.FullName `
        -CA $CaCert -CAkey $CaKey -passin stdin `
        -CAcreateserial `
        -days $LeafDays `
        -extfile $extfile.FullName `
        -out $LeafCert
    Remove-Item $extfile.FullName

    Write-Host "=== 3-5. Verify the chain ==="
    & openssl verify -CAfile $CaCert $LeafCert
}
finally {
    Remove-Item $CsrFile.FullName -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "=== Done ==="
& openssl x509 -in $LeafCert -noout -subject -dates -ext subjectAltName
Write-Host ""
Write-Host "$LeafDir is gitignored in full — nothing here should be committed."
Write-Host "Next: run the Ansible playbook to push this to the VM (roles/host_tls)."
