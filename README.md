<h1 align="center">Recon Toolkit</h1>

<p align="center">
  Automated reconnaissance scripts for bug bounty hunting and authorized penetration testing.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white"/>
  <img src="https://img.shields.io/badge/platform-linux-black?style=flat-square"/>
  <img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square"/>
</p>

---

## Overview

`recon_sh` is a full-spectrum recon automation script for bug bounty hunting and authorized penetration testing. It covers subdomain enumeration (passive, active, and permutation-based), ASN/IP discovery, live host probing, port scanning, crawling, historical URL discovery, JS/secret hunting, API endpoint discovery, cloud bucket enumeration, vulnerability-class URL filtering, screenshotting, and a known-CVE scan — all in one run.

The script skips gracefully if a required tool isn't installed, so you can run it with whatever's already on your machine and fill in gaps over time.

---

## Requirements

Install the following tools before running (Go must be installed for most of these):

```bash
go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest
go install -v github.com/projectdiscovery/katana/cmd/katana@latest
go install -v github.com/projectdiscovery/naabu/v2/cmd/naabu@latest
go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
go install github.com/lc/gau/v2/cmd/gau@latest
go install github.com/tomnomnom/waybackurls@latest
go install github.com/tomnomnom/gf@latest
go install github.com/tomnomnom/subjs@latest
go install github.com/d3mondev/puredns/v2@latest
go install github.com/Josue87/gotator@latest
go install github.com/sensepost/gowitness@latest
```

Also needed:
- `amass` — install via your package manager (`sudo pacman -S amass` on Arch) or [OWASP Amass releases](https://github.com/owasp-amass/amass)
- `cloud_enum` — clone from [initstring/cloud_enum](https://github.com/initstring/cloud_enum)
- `jq` and `curl` — `sudo pacman -S jq curl`
- `gf` patterns — needed for vuln-class filtering:
  ```bash
  mkdir -p ~/.gf
  git clone https://github.com/1ndianl33t/Gf-Patterns ~/Gf-Patterns
  cp ~/Gf-Patterns/*.json ~/.gf/
  ```
- A subdomain wordlist for brute-forcing, e.g. from [SecLists](https://github.com/danielmiessler/SecLists), placed at `~/wordlists/subdomains.txt`

---

## Usage

```bash
chmod +x recon_sh

./recon_sh example.com
```

Help / usage info:
```bash
./recon_sh --help
```

---

## What it does

1. Passive subdomain enumeration (`subfinder`, `amass`)
2. Certificate transparency lookups (`crt.sh`)
3. Active subdomain brute-forcing (`puredns`) and permutation scanning (`gotator`)
4. ASN / IP range discovery (`amass intel`)
5. Live host discovery (`httpx`)
6. Port scanning on live hosts (`naabu`)
7. Crawling for endpoints (`katana`)
8. Historical URL discovery (`gau`, `waybackurls`)
9. JS file extraction and secret/endpoint mining (`subjs` + regex grep)
10. API spec discovery (Swagger, OpenAPI, GraphQL probing)
11. Cloud storage bucket enumeration (`cloud_enum`)
12. Vulnerability-class URL filtering (`gf`: xss, ssrf, redirect, ssti, sqli, lfi, idor, rce, interestingparams, comment-inject, ssti-extended)
13. Screenshotting live hosts (`gowitness`)
14. Known CVE / misconfig scan (`nuclei`)

If a required tool isn't installed, the script asks before installing it — no silent failures, no manual pre-flight checklist.

---

## Custom gf patterns

Two extra patterns are auto-generated in `~/.gf/` on first run if missing:

- `comment-inject` — flags params like `comment=`, `message=`, `review=`, `bio=` (candidates for stored HTML/comment injection)
- `ssti-extended` — broader template-engine param matching beyond the default `ssti` pattern (`template=`, `render=`, `invoice=`, `theme=`, etc.)

Both run automatically alongside the standard pattern set and land in `gf_results/`.

---

## Output

Running the script creates a `recon_<domain>/` directory with organized subfolders (subdomains, live hosts, ports, URLs, JS files, secrets, API endpoints, cloud results, gf-filtered results, screenshots). Nothing is uploaded or sent anywhere — everything stays local.

---

## Legal / Ethical Use

These scripts are intended strictly for:
- Authorized bug bounty programs (in-scope targets only)
- Penetration tests you're contracted or authorized to perform
- Your own infrastructure

Running recon or scanning tools against systems you don't own or don't have explicit written permission to test is illegal in most jurisdictions. Always check program scope before running any of these scripts against a target.

---

## Scripts

This repo contains two recon automation scripts:

| Script | Speed | Best For | Features |
|--------|-------|----------|----------|
| `daily_recon.sh` | 10-12 min | Daily hunting, high-volume testing | Fast subdomain enum, live host check, crawling, gf filtering (XSS/SSRF/IDOR focused) |
| `full_recon.sh` | 60 min | Deep dives, thorough audits | Everything above + port scanning, API discovery, cloud bucket enum, nuclei scan, screenshots |

### Which script to use?

- **Daily hunting (15-20 domains/day):** Use `daily_recon.sh`
- **Serious audit (1-2 domains):** Use `full_recon.sh`

---

## Usage

### Fast Daily Hunting

```bash
./daily_recon.sh target.com
```

Run on multiple domains in parallel:

```bash
./daily_recon.sh target1.com &
./daily_recon.sh target2.com &
./daily_recon.sh target3.com &
```

### Full Comprehensive Recon

```bash
./full_recon.sh target.com
```

---

## Output

Both scripts create `recon_<domain>/` with results:

- `subdomains/` — discovered subdomains
- `http/` — live hosts with tech stack
- `urls/` — all crawled + historical URLs
- `gf_results/` — URLs filtered by vulnerability class (XSS, SSRF, IDOR, etc)

For `full_recon.sh` only:
- `ports/` — open ports + nuclei findings
- `api/` — API endpoints
- `cloud/` — misconfigured cloud buckets
- `screenshots/` — visual recon

---

## Recommended Workflow

1. **High-volume testing:** Use `daily_recon.sh` on 15-20 domains/day
2. **Test results:** Review `gf_results/xss.txt`, `gf_results/ssrf.txt`, etc.
3. **Manual verification:** Use dalfox, manual testing, or Burp Suite
4. **Report:** Submit findings to HackerOne/Bugcrowd
5. **Deep dive:** If promising, run `full_recon.sh` on specific targets

---

Separate download command for just daily_recon.sh:

## Download only daily_recon.sh from GitHub

```bash
curl -O https://raw.githubusercontent.com/Venu-exe/full-recon/master/daily_recon.sh

chmod +x daily_recon.sh
```
```bash
## Or use wget
wget https://raw.githubusercontent.com/Venu-exe/full-recon/master/daily_recon.sh
chmod +x daily_recon.sh
```
<p align="center">Made by <a href="https://github.com/Venu-exe">venu-exe</a></p>


