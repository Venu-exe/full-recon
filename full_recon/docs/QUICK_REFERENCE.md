# Recon Toolkit - Quick Reference Card

## One-Time Setup (Do This First)

```bash
# 1. Create directory
mkdir -p ~/bug-bounty/recon-toolkit
cd ~/bug-bounty/recon-toolkit

# 2. Copy scripts & config
cp daily_recon_FIXED.sh daily_recon.sh
cp full_recon_FIXED.sh full_recon.sh
cp triage_enhanced.sh .
cp triage.conf .

# 3. Make executable
chmod +x daily_recon.sh full_recon.sh triage_enhanced.sh

# 4. Install Go tools (CRITICAL - copy/paste all)
go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest
go install -v github.com/projectdiscovery/katana/cmd/katana@latest
go install -v github.com/projectdiscovery/naabu/v2/cmd/naabu@latest
go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
go install github.com/owasp-amass/amass/v4/cmd/amass@latest
go install github.com/d3mondev/puredns/v2@latest
go install github.com/Josue87/gotator@latest
go install github.com/lc/gau/v2/cmd/gau@latest
go install github.com/tomnomnom/waybackurls@latest
go install github.com/tomnomnom/gf@latest
go install github.com/lc/subjs@latest
go install github.com/sensepost/gowitness@latest

# 5. System packages
sudo apt-get install -y jq curl git  # Ubuntu/Debian
# OR
sudo pacman -S jq curl git           # Arch Linux
# OR
brew install jq curl git             # macOS

# 6. Setup gf patterns
mkdir -p ~/.gf
git clone https://github.com/1ndianl33t/Gf-Patterns ~/Gf-Patterns
cp ~/Gf-Patterns/*.json ~/.gf/

# 7. Create wordlists
mkdir -p ~/wordlists
cd ~/wordlists
wget https://raw.githubusercontent.com/danielmiessler/SecLists/master/Discovery/DNS/subdomains-top1million-110000.txt -O subdomains.txt
cd ~/bug-bounty/recon-toolkit

# DONE! Now test:
./daily_recon.sh example.com
```

---

## Daily Usage

### Quick Recon (10-12 min)
```bash
./daily_recon.sh domain.com

# Results in:
# recon_domain.com/triage/priority_list.txt (human-readable)
# recon_domain.com/triage/priority_list.json (for tools)
```

### View Results
```bash
# Human-readable priority list
cat recon_domain.com/triage/priority_list.txt

# JSON format for tools
cat recon_domain.com/triage/priority_list.json | jq .

# Start testing (in priority order)
cat recon_domain.com/gf_results/redirect.txt   # Test first (quick)
cat recon_domain.com/gf_results/xss.txt        # Then this (medium)
cat recon_domain.com/gf_results/idor.txt       # Finally (high-value, needs account)
```

### Full Deep Dive (60 min)
```bash
./full_recon.sh domain.com

# Generates all formats automatically:
cat recon_domain.com/triage/priority_list.txt
cat recon_domain.com/triage/priority_list.json | jq .
cat recon_domain.com/triage/priority_list.csv
cat recon_domain.com/triage/priority_list.md
```

### Test Multiple Domains in Parallel
```bash
./daily_recon.sh agoda.com &
./daily_recon.sh booking.com &
./daily_recon.sh expedia.com &
wait

# Then review all:
for d in agoda booking expedia; do
  echo "=== ${d}.com ==="
  head -20 recon_${d}.com/triage/priority_list.txt
done
```

---

## Manual Testing Workflow

### 1. Open Redirects (Fastest ⚡)
```bash
cat recon_domain.com/gf_results/redirect.txt | head -20

# For each URL with param like: domain.com/login?url=
# 1. Change param to: attacker.com
# 2. Check if redirect happens
# Time: ~10 sec per URL
```

### 2. XSS (Medium Speed ⚡⚡)
```bash
cat recon_domain.com/gf_results/xss.txt | head -20

# For each URL:
# 1. Try: param=<img src=x onerror=alert(1)>
# 2. View page source
# 3. If reflected, it's XSS
# Time: ~1-2 min per URL
```

### 3. IDOR (Highest Value but Slowest ⚡⚡⚡)
```bash
cat recon_domain.com/gf_results/idor.txt | head -20

# Requires your own account:
# 1. Login with your account
# 2. Intercept request with YOUR user_id/order_id
# 3. Change to DIFFERENT user's ID
# 4. Check if you access their data
# Time: ~2-5 min per URL (needs real account)
```

---

## File Structure

```
~/bug-bounty/recon-toolkit/
├── daily_recon.sh           # Use for 10-12 min recon
├── full_recon.sh            # Use for 60 min deep dive
├── triage_enhanced.sh       # Auto-prioritization
├── triage.conf              # Triage config
├── README.md                # Main docs
│
└── recon_DOMAIN/            # Auto-generated per domain
    ├── subdomains/
    │   ├── final.txt
    │   └── NEW_subdomains.txt      # Test these first
    ├── http/
    │   └── live_urls.txt
    ├── urls/
    │   ├── all_urls.txt
    │   ├── with_params.txt
    │   └── NEW_urls.txt            # New since last run
    ├── gf_results/                 # Filtered by vuln type
    │   ├── redirect.txt            # Open redirect candidates
    │   ├── xss.txt                 # XSS candidates
    │   ├── idor.txt                # IDOR candidates
    │   ├── ssrf.txt
    │   └── ...
    └── triage/                     # Auto-generated priority lists
        ├── priority_list.txt       # Human-readable
        ├── priority_list.json      # For tools
        ├── priority_list.csv       # For spreadsheets
        └── priority_list.md        # For reports
```

---

## Customization by Target Type

### Travel/Booking (Agoda, Booking.com, Expedia)
```bash
# Edit triage.conf and add:
IDOR_PARAMS="$IDOR_PARAMS hotel_id room_id flight_id guest_id booking_id"
TEXT_PARAMS="$TEXT_PARAMS checkin checkout destination"
```

### E-Commerce (Amazon, eBay, Etsy)
```bash
IDOR_PARAMS="$IDOR_PARAMS order_id product_id seller_id cart_id"
TEXT_PARAMS="$TEXT_PARAMS price title description"
```

### SaaS/Productivity (Slack, Trello, Asana)
```bash
IDOR_PARAMS="$IDOR_PARAMS workspace_id team_id project_id document_id"
TEXT_PARAMS="$TEXT_PARAMS message task comment"
```

### Social Networks (Twitter, LinkedIn, Reddit)
```bash
IDOR_PARAMS="$IDOR_PARAMS user_id profile_id post_id group_id"
TEXT_PARAMS="$TEXT_PARAMS bio status tweet"
```

---

## Performance Tips

| Task | Time | Commands |
|------|------|----------|
| Single quick recon | 10-12 min | `./daily_recon.sh domain.com` |
| 3 domains parallel | 35-40 min | `./daily_recon.sh d1.com & ./daily_recon.sh d2.com & ./daily_recon.sh d3.com & wait` |
| Single full recon | 60 min | `./full_recon.sh domain.com` |
| Test 1 redirect | 10 sec | 1 URL = 10 sec |
| Test 1 XSS | 1-2 min | 1 URL = 1-2 min |
| Test 1 IDOR | 2-5 min | Needs real account |
| Per-day hunting (15 domains) | ~2.5-3 hours | Parallel testing |

---

## Priority Testing Order

After recon completes, test in THIS order (highest ROI first):

1. **Open Redirects** (quick yes/no, rarely get)
2. **XSS** (moderate difficulty, common)
3. **IDOR** (hardest but highest severity, needs account)
4. **SSRF** (rare, requires deep knowledge)
5. **Other findings** (if applicable)

---

## Reporting & Exports

### For Spreadsheet Tracking
```bash
# CSV is spreadsheet-friendly
cat recon_domain.com/triage/priority_list.csv
# Open in Excel/Google Sheets
```

### For GitHub/Wiki
```bash
# Markdown format
cat recon_domain.com/triage/priority_list.md
```

### For Automation/APIs
```bash
# JSON format
cat recon_domain.com/triage/priority_list.json | jq .
```

### For HackerOne/Bugcrowd Reports
```bash
# Use priority_list.txt as your testing checklist
cat recon_domain.com/triage/priority_list.txt
```

---

## Common Issues & Fixes

| Issue | Fix |
|-------|-----|
| `command not found: subfinder` | `export PATH="$PATH:$(go env GOPATH)/bin"` then add to ~/.bashrc |
| `httpx not found` | `go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest` |
| `triage_enhanced.sh not found` | Copy triage_enhanced.sh to same directory as daily_recon.sh |
| `Can't find gf_results` | Make sure daily_recon.sh completed fully (check live_urls.txt exists) |
| `Empty gf results` | Normal if no XSS/SSRF/IDOR patterns matched - no findings = no files |

---

## One-Liner Cheat Codes

```bash
# Run 5 domains in background
for d in agoda booking expedia trivago musement; do
  ./daily_recon.sh "${d}.com" &
done; wait

# View all priority lists
for d in recon_*/; do
  echo "=== ${d%/} ==="
  head -10 "${d}triage/priority_list.txt"
done

# Count findings per domain
for d in recon_*/; do
  echo "${d%/}: $(wc -l < "${d}gf_results/xss.txt" 2>/dev/null || echo 0) XSS, $(wc -l < "${d}gf_results/idor.txt" 2>/dev/null || echo 0) IDOR"
done

# Export all CSVs to one file
(echo "Domain,Type,Parameter,URL"; for d in recon_*/; do 
  domain="${d%/*}"; 
  tail -n +2 "${d}triage/priority_list.csv" 2>/dev/null | sed "s/^/${domain},/" 
done) > all_findings.csv

# Copy all results to external drive
cp -r recon_*/ /media/external-drive/bug-bounty-results/
```

---

## Documentation Files

| File | Purpose |
|------|---------|
| `BUGS_FIXED_SUMMARY.md` | What was broken & how it was fixed |
| `COMPLETE_SETUP_GUIDE.md` | Detailed 7-step setup process |
| `TRIAGE_README.md` | How to use & customize triage script |
| `QUICK_REFERENCE.md` | This file - quick copy/paste commands |

---

## Next Steps

1. ✅ Copy scripts using one-time setup above
2. ✅ Test: `./daily_recon.sh example.com`
3. ✅ Review: `cat recon_example.com/triage/priority_list.txt`
4. ✅ Start testing (redirect → XSS → IDOR order)
5. ✅ Submit findings to HackerOne/Bugcrowd

---

**You're ready to hunt! 🎯**

Bookmark this file for quick reference during testing sessions.
