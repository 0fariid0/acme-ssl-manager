# ACME SSL Manager

A modern Bash menu for managing SSL certificates on Linux servers with [`acme.sh`](https://github.com/acmesh-official/acme.sh).

This script is designed for VPS/server admins who want a simple terminal menu to issue, renew, remove, inspect, diagnose, repair, and back up SSL certificates.

Repository:

```bash
https://github.com/0fariid0/acme-ssl-manager
```

Current version: `1.1.0`

---

## Features

- Modern English terminal menu with colored UI
- Automatic `acme.sh` installation if missing
- Automatic installation of required tools such as `curl`, `openssl`, `ca-certificates`, and `socat`
- View certificates managed by `acme.sh`
- Show certificate expiration date and remaining time
- Show installed certificate paths
- Issue new SSL certificates
- Renew one certificate
- Renew all certificates
- Remove certificates from `acme.sh`
- Optional revoke before removing
- Backup installed certificates
- Diagnostics for ports `80` and `443`
- ACME API connectivity preflight test
- Network/TLS repair option for cURL/OpenSSL/CA certificate issues
- Optional temporary Force IPv4 mode for ACME operations
- Detect Apache, Nginx, Caddy, and HAProxy
- Temporarily stop active web services before standalone SSL issuance
- Restore only the services that were stopped by the script

---

## Requirements

Supported Linux distributions:

- Ubuntu
- Debian
- AlmaLinux
- Rocky Linux
- CentOS
- Fedora
- Alpine Linux

Required public ports:

- `80` for HTTP-01 validation
- `443` for TLS-ALPN-01 validation

For normal Let's Encrypt HTTP validation, port `80` must be reachable from the internet.

---

## Quick Run

Run directly from GitHub:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/0fariid0/acme-ssl-manager/main/ssl-manager.sh)
```

Alternative with `wget`:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/0fariid0/acme-ssl-manager/main/ssl-manager.sh)
```

---

## Install as a Local Command

Install the manager as `sslmgr`:

```bash
curl -Ls -o /usr/local/bin/sslmgr https://raw.githubusercontent.com/0fariid0/acme-ssl-manager/main/ssl-manager.sh
chmod +x /usr/local/bin/sslmgr
sslmgr
```

After installation, you can open the menu anytime with:

```bash
sslmgr
```

---

## Manual Installation

Clone the repository:

```bash
git clone https://github.com/0fariid0/acme-ssl-manager.git
cd acme-ssl-manager
chmod +x ssl-manager.sh
./ssl-manager.sh
```

---

## Menu Options

```text
1) View certificates and remaining time
2) Issue new certificate
3) Renew one certificate
4) Renew all certificates
5) Remove certificate
6) Show cert/key paths
7) Backup certificates
8) Diagnostics
9) Install/Update local command: sslmgr
10) Upgrade acme.sh
11) Register/Update Let's Encrypt account email
12) Network/TLS repair & ACME preflight
0) Exit
```

---

## Certificate Paths

Issued certificates are installed here:

```bash
/etc/acme-ssl-manager/certs/DOMAIN/
```

Main files:

```bash
/etc/acme-ssl-manager/certs/DOMAIN/private.key
/etc/acme-ssl-manager/certs/DOMAIN/fullchain.pem
/etc/acme-ssl-manager/certs/DOMAIN/cert.pem
/etc/acme-ssl-manager/certs/DOMAIN/ca.pem
```

For most panels such as x-ui, 3x-ui, Nginx, HAProxy, and similar tools, you usually need:

```bash
Private Key: /etc/acme-ssl-manager/certs/DOMAIN/private.key
Full Chain:  /etc/acme-ssl-manager/certs/DOMAIN/fullchain.pem
```

Replace `DOMAIN` with your real domain name.

Example:

```bash
/etc/acme-ssl-manager/certs/example.com/private.key
/etc/acme-ssl-manager/certs/example.com/fullchain.pem
```

---

## Troubleshooting: Could not get nonce / cURL error 35

If you see an error like this:

```text
Could not get nonce
Please refer to https://curl.haxx.se/libcurl/c/libcurl-errors.html for error code: 35
Error creating new order. Le_OrderFinalize not found.
```

This usually means the server could not connect to the Let's Encrypt ACME API over HTTPS. It often happens because of one of these issues:

- Broken or outdated CA certificates
- Old curl/OpenSSL packages
- Server time is wrong
- IPv6 is broken, but the server tries IPv6 first
- Provider firewall blocks outbound HTTPS to Let's Encrypt
- Temporary Let's Encrypt/API connectivity issue

Use this menu option first:

```text
12) Network/TLS repair & ACME preflight
```

Then try issuing the certificate again. If the preflight says IPv4 works but IPv6 fails, answer `y` when the script asks:

```text
Force IPv4 for outgoing ACME API requests? [y/N]: y
```

Manual repair commands for Debian/Ubuntu:

```bash
apt-get update
apt-get install -y curl openssl ca-certificates socat
update-ca-certificates
timedatectl set-ntp true
~/.acme.sh/acme.sh --upgrade
~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
```

Manual connectivity tests:

```bash
curl -Iv https://acme-v02.api.letsencrypt.org/directory
curl -4Iv https://acme-v02.api.letsencrypt.org/directory
curl -6Iv https://acme-v02.api.letsencrypt.org/directory
```

---

## Important Notes

### Port 80

For HTTP-01 validation, Let's Encrypt must be able to reach your server on public port `80`.

If another service is using port `80`, this script can temporarily stop common web services such as Apache, Nginx, Caddy, or HAProxy while issuing the certificate.

After the certificate operation finishes, the script restores only the services that it stopped.

### Port 443

For TLS-ALPN-01 validation, public port `443` must be reachable.

### Cloudflare

If your domain is behind Cloudflare proxy, standalone HTTP validation may fail depending on your configuration.

Recommended options:

- Temporarily turn off the orange cloud proxy and use DNS-only mode
- Or use a DNS API validation method manually through `acme.sh`

---

## Backup Location

Backups are stored here:

```bash
/etc/acme-ssl-manager/backups/
```

---

## Update acme.sh

You can update `acme.sh` from inside the menu:

```text
10) Upgrade acme.sh
```

Or manually:

```bash
~/.acme.sh/acme.sh --upgrade
```

---

## Uninstall Local Command

To remove only the local command:

```bash
rm -f /usr/local/bin/sslmgr
```

This does not remove certificates or `acme.sh`.

---

## Safety Behavior

The script does not blindly restart all services.

When issuing or renewing certificates in standalone mode:

1. It checks which web services are active.
2. It stops only the active services that may block the required port.
3. It runs the certificate operation.
4. It starts only the services that were stopped by the script.

This avoids accidentally starting disabled services.

---

## License

MIT License
