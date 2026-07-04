# 🎯 Recon Toolkit - Printable Checklist

Print this page and use it as your reference during setup and hunting!

---

## ✅ SETUP CHECKLIST (Do Once)

### BEFORE RUNNING SCRIPTS
- [ ] Copy `daily_recon_FIXED.sh` → rename to `daily_recon.sh`
- [ ] Copy `full_recon_FIXED.sh` → rename to `full_recon.sh`
- [ ] Copy `triage_enhanced.sh` to same directory
- [ ] Copy `triage.conf` to same directory
- [ ] Make scripts executable: `chmod +x *.sh`

### INSTALL GO TOOLS
```bash
# Run each line (copy/paste all):
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
```
- [ ] All tools installed

### INSTALL SYSTEM PACKAGES
```bash
# Ubuntu/Debian:
sudo apt-get install -y jq curl git

# Arch:
sudo pacman -S jq curl git

# macOS:
brew install jq curl git
```
- [ ] jq installed
- [ ] curl installed
- [ ] git installed

### SETUP GF PATTERNS
```bash
mkdir -p ~/.gf
git clone https://github.com/1ndianl33t/Gf-Patterns ~/Gf-Patterns
cp ~/Gf-Patterns/*.json ~/.gf/
```
- [ ] gf patterns installed

### CREATE WORDLISTS
```bash
mkdir -p ~/wordlists
cd ~/wordlists
wget https://raw.githubusercontent.com/danielmiessler/SecLists/master/Discovery/DNS/subdomains-top1million-110000.txt -O subdomains.txt
```
- [ ] Wordlist downloaded

### VERIFY SETUP
```bash
# All should return paths/versions:
which subfinder
which httpx
which gf
ls ~/.gf/*.json | wc -l  # Should be 20+
ls ~/wordlists/subdomains.txt
```
- [ ] All tools found and working

---

## 🎯 DAILY HUNTING CHECKLIST

### BEFORE EACH RUN
- [ ] Target domain confirmed in-scope (check HackerOne/Bugcrowd scope)
- [ ] Working directory ready: `cd ~/bug-bounty/recon-toolkit`
- [ ] No other recons running: `ps aux | grep daily_recon`

### QUICK RECON (10-12 minutes)
```bash
./daily_recon.sh target.com
# Will auto-generate triage output
```
- [ ] Command started
- [ ] Wait for completion
- [ ] Check output exists: `ls recon_target.com/triage/`

### VIEW RESULTS
```bash
# Human-readable priority list
cat recon_target.com/triage/priority_list.txt

# OR machine-readable
cat recon_target.com/triage/priority_list.json | jq .
```
- [ ] Priority list reviewed

### MANUAL TESTING PRIORITY ORDER
- [ ] **First:** Open redirects (quick, ~10 sec each)
  ```bash
  head -20 recon_target.com/gf_results/redirect.txt
  ```
- [ ] **Second:** XSS/Text (medium, ~1-2 min each)
  ```bash
  head -20 recon_target.com/gf_results/xss.txt
  ```
- [ ] **Third:** IDOR (slow but high-value, ~2-5 min each, needs account)
  ```bash
  head -20 recon_target.com/gf_results/idor.txt
  ```

---

## 📊 PARALLEL TESTING (3 Domains)

```bash
# Start all 3 at once
./daily_recon.sh agoda.com &
./daily_recon.sh booking.com &
./daily_recon.sh expedia.com &

# Wait for all to finish
wait

# Review all results
for d in recon_*/; do
  echo "=== ${d%/} ==="
  head -10 "${d}triage/priority_list.txt"
done
```

- [ ] All 3 domains started
- [ ] All 3 completed
- [ ] Results reviewed

---

## 🏆 VULNERABILITY TESTING QUICK GUIDE

### OPEN REDIRECT (Test First - Fastest)
| Step | Action | Time |
|------|--------|------|
| 1 | Copy URL from `gf_results/redirect.txt` | 5 sec |
| 2 | Change param value to `attacker.com` | 5 sec |
| Time per URL | ~10 seconds | |

**Test on:** `url=`, `return=`, `next=`, `redirect=` parameters

---

### XSS/TEXT REFLECTION (Test Second)
| Step | Action | Time |
|------|--------|------|
| 1 | Copy URL from `gf_results/xss.txt` | 10 sec |
| 2 | Try: `param=<img src=x onerror=alert(1)>` | 30 sec |
| 3 | View page source (Ctrl+U) | 10 sec |
| 4 | Check if payload reflected | 20 sec |
| Time per URL | ~1-2 minutes | |

**Test on:** `q=`, `search=`, `name=`, `comment=` parameters

---

### IDOR (Test Third - Highest Value)
| Step | Action | Time |
|------|--------|------|
| 1 | Login with YOUR account | 30 sec |
| 2 | Find endpoint with user_id param | 30 sec |
| 3 | Intercept request (Burp) | 30 sec |
| 4 | Change YOUR id to different user's id | 30 sec |
| 5 | See if you access their data | 1 min |
| Time per URL | ~2-5 minutes | |

**Test on:** `user_id=`, `account_id=`, `order_id=`, `hotel_id=` parameters

---

## 📈 DAILY TRACKING

```
Date: ____________

Domains Tested: ________
Vulnerabilities Found: ________
Highest Severity: ________
Reports Submitted: ________
Notes: _____________________
```

---

## 🚨 TROUBLESHOOTING QUICK FIXES

| Problem | Quick Fix |
|---------|-----------|
| `command not found: subfinder` | `export PATH="$PATH:$(go env GOPATH)/bin"` + add to ~/.bashrc |
| `httpx not found` | `go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest` |
| `triage_enhanced.sh not found` | Copy script to same directory as daily_recon.sh |
| `Can't find recon_DOMAIN/triage` | Wait for daily_recon to complete fully (12 min) |
| `Empty gf_results` | Normal - just means no XSS/SSRF/IDOR patterns matched |
| Script returns: `mkdir: permission denied` | Fix: `chmod 755 ~/bug-bounty/recon-toolkit` |

---

## 💡 QUICK COMMANDS (Copy/Paste)

### View Priority List
```bash
cat recon_DOMAIN/triage/priority_list.txt
```

### View as JSON
```bash
cat recon_DOMAIN/triage/priority_list.json | jq .
```

### View as CSV
```bash
cat recon_DOMAIN/triage/priority_list.csv
```

### Count Findings
```bash
wc -l recon_DOMAIN/gf_results/*.txt
```

### Test 3 Domains Parallel
```bash
./daily_recon.sh domain1.com &
./daily_recon.sh domain2.com &
./daily_recon.sh domain3.com &
wait
```

### View NEW Subdomains (freshest targets)
```bash
cat recon_DOMAIN/subdomains/NEW_subdomains.txt
```

### Export to CSV
```bash
cat recon_DOMAIN/triage/priority_list.csv > report.csv
```

---

## 🎓 DOCUMENTATION QUICK LINKS

| Need | Read This | Time |
|------|-----------|------|
| Quick start | QUICK_REFERENCE.md | 5 min |
| Full setup | COMPLETE_SETUP_GUIDE.md | 30 min |
| Understand issues | BUGS_FIXED_SUMMARY.md | 10 min |
| Big picture | WHAT_YOU_HAVE_NOW.md | 15 min |
| Customization | TRIAGE_README.md | 20 min |
| Navigation | START_HERE_MASTER_INDEX.md | 5 min |

---

## ✨ SUCCESS METRICS (Track Progress)

**Week 1 Goals:**
- [ ] Complete setup
- [ ] Run 5+ domains with quick recon
- [ ] Find 1-2 vulnerabilities
- [ ] Submit first report

**Week 2-4 Goals:**
- [ ] Run 10+ domains per week
- [ ] Find 3-5 vulnerabilities
- [ ] Submit 3-5 reports
- [ ] Build reputation

**Month 2 Goals:**
- [ ] Run 15-20 domains per week
- [ ] Find 5-10 vulnerabilities
- [ ] Submit 5-10 reports
- [ ] Consistent monthly income

---

## 🎯 HUNTING WORKFLOW (Copy This)

```
1. SETUP (once)
   └─ Follow setup checklist above

2. DAILY HUNT (repeat)
   ├─ Check scope on HackerOne
   ├─ ./daily_recon.sh target.com
   ├─ Wait 12 minutes
   ├─ cat recon_target.com/triage/priority_list.txt
   ├─ Test open redirects (10 min)
   ├─ Test XSS (20 min)
   ├─ Test IDOR if you have account (30 min)
   ├─ If found: submit to HackerOne
   └─ If not found: next domain

3. WEEKLY REVIEW
   └─ Count vulnerabilities found
   └─ Optimize your process
   └─ Adjust target selection
```

---

## 📋 FINAL CHECKLIST (Before Hunting)

- [ ] All tools installed and in PATH
- [ ] Scripts copied and executable
- [ ] Test run successful: `./daily_recon.sh example.com`
- [ ] Understand vulnerability testing methods
- [ ] Know your target's scope
- [ ] Have HackerOne/Bugcrowd open
- [ ] Ready to submit findings

---

## 🎯 YOU'RE READY!

If you've completed the setup checklist above, you're ready to hunt.

**Next step:** Pick your first target and run:
```bash
./daily_recon.sh yourtarget.com
```

**Happy hunting!** 🚀

---

**Print this page and keep it nearby during setup and hunting!**
