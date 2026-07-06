# 🎯 Full-Recon - Bug Bounty Reconnaissance Toolkit

<p align="center">
  <img src="https://img.shields.io/badge/bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white"/>
  <img src="https://img.shields.io/badge/fish-3D7E3C?style=flat-square&logo=fish&logoColor=white"/>
  <img src="https://img.shields.io/badge/platform-linux%20|%20arch-black?style=flat-square"/>
  <img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square"/>
</p>

---

## 📋 Overview

**Full-Recon** is a complete, automated reconnaissance toolkit for bug bounty hunting and authorized penetration testing. It performs subdomain enumeration, live host discovery, URL crawling, vulnerability pattern filtering, and automatic triage - all in one command.

**Two Scripts:**
- **`daily_recon.sh`** - Fast recon in 10-12 minutes (perfect for high-volume hunting)
- **`full_recon.sh`** - Comprehensive recon in 60 minutes (for serious audits)

Both automatically generate **priority lists** organized by vulnerability type (Open Redirect, XSS, IDOR, SSRF) and push results to GitHub.

---

## ⚡ Quick Start

### 1. Install Tools (One-Time Setup)

```bash
# Arch Linux
sudo pacman -S jq curl git base-devel go

# Ubuntu/Debian
sudo apt-get install -y jq curl git build-essential golang-go

# Then install Go tools:
go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest
go install -v github.com/projectdiscovery/katana/cmd/katana@latest
go install github.com/owasp-amass/amass/v4/cmd/amass@latest
go install github.com/lc/gau/v2/cmd/gau@latest
go install github.com/tomnomnom/gf@latest

# Full list in docs/COMPLETE_SETUP_GUIDE.md
```

### 2. Copy Scripts to Your PATH

```fish
# Create bin directory
mkdir -p ~/.local/bin
cp daily_recon.sh ~/.local/bin/
cp full_recon.sh ~/.local/bin/
cp triage_enhanced.sh ~/.local/bin/
chmod +x ~/.local/bin/daily_recon.sh
chmod +x ~/.local/bin/full_recon.sh
chmod +x ~/.local/bin/triage_enhanced.sh

# Add to PATH (one-time, Fish Shell)
echo 'set -Uxa PATH ~/.local/bin' >> ~/.config/fish/config.fish
source ~/.config/fish/config.fish
```




### 4. Run Your First Recon

```fish
# From anywhere
daily_recon.sh example.com

# Wait 12 minutes...
# View priority list
cat recon_example.com/triage/priority_list.txt
```

---

## 🚀 Usage

### Quick Recon (10-12 minutes)

```fish
daily_recon.sh target.com
```

**Covers:**
- Subdomain enumeration (passive)
- Live host discovery
- URL crawling
- Vulnerability pattern filtering
- Automatic triage & prioritization

**Output:** `recon_target.com/triage/priority_list.txt`

---

### Full Comprehensive Recon (60 minutes)

```fish
full_recon.sh target.com
```

**Covers:**
- Everything in quick recon, PLUS:
- Active subdomain brute-forcing
- Port scanning
- JS file discovery & secret mining
- API endpoint discovery
- Cloud bucket enumeration
- Screenshots
- CVE scanning

**Output:** Multiple formats (text, JSON, CSV, Markdown)

---

### View Results

```fish
# Human-readable priority list
cat recon_target.com/triage/priority_list.txt

# Machine-readable (JSON)
cat recon_target.com/triage/priority_list.json | jq .

# Spreadsheet format (CSV)
cat recon_target.com/triage/priority_list.csv

# Report format (Markdown)
cat recon_target.com/triage/priority_list.md

# View on GitHub
https://github.com/Venu-exe/full-recon.git
```

---

### High-Volume Testing

```fish
# Test 5 domains in parallel (completes in ~12 min instead of 60 min)
daily_recon.sh site1.com &
daily_recon.sh site2.com &
daily_recon.sh site3.com &
daily_recon.sh site4.com &
daily_recon.sh site5.com &
wait

# Review all results
for domain in site1 site2 site3 site4 site5; do
  echo "=== ${domain}.com ==="
  head -10 recon_${domain}.com/triage/priority_list.txt
done
```

---

## 📊 What Gets Generated

After running `daily_recon.sh target.com`:

```
recon_target.com/
├── subdomains/
│   ├── final.txt              # All discovered subdomains
│   └── NEW_subdomains.txt     # New since last run (test first!)
├── http/
│   ├── live_urls.txt          # All live hosts
│   └── live_urls_filtered.txt # Live hosts (noise removed)
├── urls/
│   ├── all_urls.txt           # All discovered URLs
│   ├── with_params.txt        # URLs with query parameters
│   └── NEW_urls.txt           # New since last run
├── gf_results/                # Filtered by vulnerability type
│   ├── redirect.txt           # Open redirect candidates
│   ├── xss.txt                # XSS candidates
│   ├── idor.txt               # IDOR candidates
│   ├── ssrf.txt               # SSRF candidates
│   └── ...
└── triage/                    # ✨ Auto-generated priority lists
    ├── priority_list.txt      # Human-readable
    ├── priority_list.json     # Machine-readable
    ├── priority_list.csv      # Spreadsheet format
    └── priority_list.md       # Report format
```

---

## ✨ Recent Improvements

### Noise Filtering
- Now excludes: Google, Facebook, Stripe, PayPal, Okta, Auth0, Slack, etc.
- Cuts out ~60% of useless third-party hosts
- Results are ~90% more actionable

### GitHub Integration
- Results auto-commit + push to GitHub repo
- Perfect for tracking findings over time
- Share findings with team

### Enhanced Triage
- Auto-generates priority lists in 4 formats (text, JSON, CSV, Markdown)
- Sorts by vulnerability type (Open Redirect, XSS, IDOR, SSRF)
- Highlights NEW findings since last run

---

## 🎯 Testing Priority Order

After recon completes, test vulnerabilities in this order:

### 1. **Open Redirects** (Fastest, ~10 sec each)
```fish
cat recon_target.com/gf_results/redirect.txt | head -20
# Test by changing param to: attacker.com
```

### 2. **XSS** (Medium, ~1-2 min each)
```fish
cat recon_target.com/gf_results/xss.txt | head -20
# Test by injecting: <img src=x onerror=alert(1)>
```

### 3. **IDOR** (Highest value, ~2-5 min each, needs real account)
```fish
cat recon_target.com/gf_results/idor.txt | head -20
# Test by changing YOUR user_id to different user's ID
```

---

## 🔗 GitHub Integration Workflow

```fish
# 1. Quick recon
daily_recon.sh target.com

# 2. Results auto-push to:
# https://github.com/Venu-exe/full-recon.git

# 3. View priority list (any format)
cat ~/bug-bounty-recon/findings/target.com/triage/priority_list.txt
cat ~/bug-bounty-recon/findings/target.com/triage/priority_list.json | jq .

# 4. Test manually
# Start with NEW findings first (less-tested = higher success)
cat ~/bug-bounty-recon/findings/target.com/urls/NEW_urls.txt | head -10
```

---

## 📚 Documentation

Complete guides in the `docs/` folder:

| Document | Purpose |
|----------|---------|
| **START_HERE.md** | Navigation guide & quick overview |
| **COMPLETE_SETUP_GUIDE.md** | Detailed 7-step setup process |
| **QUICK_REFERENCE.md** | Copy/paste commands for daily use |
| **TRIAGE_README.md** | How to customize triage for your targets |
| **GITHUB_SETUP.md** | GitHub integration & troubleshooting |
| **CHANGELOG.md** | What's new in each version |

**Start here:** `docs/START_HERE.md`

---

## 🔧 Customization

### For Your Target Type

Edit `triage.conf` and add parameters specific to your target:

**Travel/Booking:**
```bash
IDOR_PARAMS="$IDOR_PARAMS hotel_id room_id flight_id booking_id"
```

**E-Commerce:**
```bash
IDOR_PARAMS="$IDOR_PARAMS order_id product_id cart_id"
```

**SaaS:**
```bash
IDOR_PARAMS="$IDOR_PARAMS workspace_id team_id project_id"
```

See `docs/TRIAGE_README.md` for more customization options.

---

## 🛠️ Requirements

### System
- Linux (Arch, Ubuntu, Debian tested)
- Bash 4+
- jq, curl, git

### Go Tools (install via `go install`)
- subfinder - passive subdomain enumeration
- httpx - live host probing
- katana - crawling
- amass - ASN/IP discovery
- naabu - port scanning
- nuclei - vulnerability scanning
- gau, waybackurls - historical URL discovery
- gf - URL pattern filtering
- subjs - JS file discovery
- gowitness - screenshots

**See `docs/COMPLETE_SETUP_GUIDE.md` for full installation.**

---

## 🚨 Important Notes

⚠️ **Legal:** Only use against targets you own or have explicit written permission to test.

✅ **Scope:** Always verify your target is in-scope before running any recon.

🎯 **Speed:** Quick recon focuses on high-probability bugs (XSS, SSRF, IDOR, redirects).

📊 **Accuracy:** Results are deduplicated and filtered to remove noise.

---

## 📈 Expected Results

### After `daily_recon.sh` on medium-sized web application:
- 500-1000 subdomains
- 50-100 live hosts
- 5,000-20,000 unique URLs
- 50-200 **high-quality** vulnerability candidates (noise filtered)
- Auto-generated priority list (text, JSON, CSV, Markdown)
- Auto-pushed to GitHub ✨

**Time:** 10-12 minutes
**Output:** `~/bug-bounty-recon/findings/target.com/`

---

### After `full_recon.sh` on same target:
- Everything above, PLUS:
- 1000+ open ports
- 100+ JS files
- API endpoints found
- Cloud buckets enumerated
- Known CVEs identified
- Screenshots of all hosts

**Time:** ~60 minutes

---

## 💡 Pro Tips

1. **Test NEW findings first** - Each run identifies fresh subdomains/URLs (less-tested = higher success)
2. **Use parallel testing** - Run 3-5 domains simultaneously
3. **Customize for your target** - Edit `triage.conf` based on target type
4. **Batch test high-volume** - 15-20 domains/day workflow
5. **Combine with manual testing** - Automation finds URLs, YOU find vulnerabilities

---

## 🤝 Contributing

Found a bug? Have improvements? Submit a pull request!

Areas for contribution:
- Additional gf patterns
- New vulnerability filters
- Tool integrations
- Documentation improvements

---

## 📝 License

MIT License - See LICENSE file

---

## 🎓 Workflow Example

```fish
# 1. Setup (one-time)
sudo pacman -S go jq curl git
go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
# ... install other tools
git clone https://github.com/YOUR_USERNAME/bug-bounty-recon.git ~/bug-bounty-recon

# 2. Daily hunting
daily_recon.sh target1.com        # 12 min
view recon_target1.com/triage/priority_list.txt
# Manual testing on priority findings (30-60 min)

# 3. Results auto-pushed to GitHub
# https://github.com/Venu-exe/full-recon.git

# 4. Submit findings
# Create report on HackerOne/Bugcrowd
# Earn bounty!

# 5. Repeat with next target
daily_recon.sh target2.com &
daily_recon.sh target3.com &
# ... test 15-20 domains/day
```

---

## 📞 Need Help?

1. **Quick start:** Read `docs/START_HERE.md`
2. **Full setup:** Follow `docs/COMPLETE_SETUP_GUIDE.md`
3. **Daily reference:** Use `docs/QUICK_REFERENCE.md`
4. **Customization:** See `docs/TRIAGE_README.md`
5. **GitHub help:** Check `docs/GITHUB_SETUP.md`

---

## 🎯 Quick Stats

| Metric | Value |
|--------|-------|
| Setup time | ~1 hour |
| Quick recon time | 10-12 min per domain |
| Full recon time | ~60 min per domain |
| Domains/day (quick) | 15-20 |
| Learning curve | Beginner-friendly |
| Effectiveness | High (focuses on high-probability vulns) |
| Noise filtering | ~60% reduction in useless hosts |

---

## ✨ Made by

[venu-exe](https://github.com/Venu-exe) - Bug bounty researcher & penetration tester

---

**Start hunting today!** 🚀

```fish
daily_recon.sh your-target.com
```

---

<p align="center">
  <strong>⭐ If this helped you, consider giving it a star!</strong>
</p>
