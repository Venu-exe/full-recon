# IDOR Prober v2.0
Automated IDOR vulnerability scanner for authorized security testing and bug bounty hunting

![Language](https://img.shields.io/badge/Language-C-blue.svg)
![Platform](https://img.shields.io/badge/Platform-Linux-lightgrey.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)

## What is IDOR?
Insecure Direct Object Reference (IDOR) is an access control vulnerability that arises when an application provides direct access to objects based on user-supplied input. As a result, attackers can bypass authorization and access resources belonging to other users directly, such as database records, files, or sensitive data.

## How It Works
IDOR Prober utilizes a dual-session testing approach to identify vulnerabilities accurately:
- Takes two authenticated sessions (User A, User B)
- Fetches the same resource with both sessions
- Compares JSON responses using shape similarity (Jaccard index) + value similarity
- Optionally compares against B's own baseline resource
- Classifies the result: IDOR_CONFIRMED, DENIED, SAFE_REMAPPED, AMBIGUOUS, NOT_JSON

## Features (v2.0)
- Multi-HTTP-method support (GET, POST, PUT, DELETE, PATCH)
- Multi-threaded concurrent scanning with pthreads thread pool
- Rate limiting (token-bucket algorithm)
- Automatic ID enumeration with {ID} URL templates
- JSON report output for tool integration
- HTML report output with dark theme and sortable table
- ANSI colored terminal output with progress bar
- Response header security analysis (CSP, HSTS, X-Frame-Options, Cache-Control)
- Configuration file support (key=value format)
- Baseline comparison for false positive reduction
- JSON structural diffing using shape + value similarity

## Project Structure
```
idor_prober/
|-- Makefile
|-- include/
|   |-- http_client.h
|   |-- json_diff.h
|   |-- reporter.h
|   |-- thread_pool.h
|   |-- rate_limit.h
|   |-- header_analysis.h
|   |-- config.h
|-- src/
|   |-- main.c
|   |-- http_client.c
|   |-- json_diff.c
|   |-- reporter.c
|   |-- thread_pool.c
|   |-- rate_limit.c
|   |-- header_analysis.c
|   |-- config.c
|-- lib/
|   |-- cJSON.c
|   |-- cJSON.h
|-- test/
|   |-- mock_server.py
|   |-- sessionA.txt
|   |-- sessionB.txt
|   |-- sessionC.txt
|   |-- sample_config.txt
|   |-- urls.txt
|-- LICENSE
|-- README.md
```

## Dependencies
- gcc (C compiler)
- libcurl (with development headers)
- pthreads (usually included with glibc)
- Python 3 (for mock server only)

Install command for Debian/Ubuntu:
```bash
sudo apt-get install gcc libcurl4-openssl-dev make
```

For Arch:
```bash
sudo pacman -S gcc curl make
```

## Build
```bash
git clone https://github.com/Venu-exe/full-recon.git
cd full-recon/finalyearpro/idor_prober
make
```

## Usage
```
idor_prober v2.0 - dual-session access control prober

Usage:
  ./idor_prober -A <sessionA.txt> -B <sessionB.txt> -u <url> [options]
  ./idor_prober -A <sessionA.txt> -B <sessionB.txt> -l <urls.txt> [options]
  ./idor_prober -A <sessionA.txt> -B <sessionB.txt> -u <url_template> -e <range> [options]
  ./idor_prober -c <config.txt> [options]

Session file format (one directive per line):
  Cookie: session=abc123; other=value
  Authorization: Bearer eyJ...
  Header: X-Api-Key: value

Core options:
  -u   single target URL (A's resource, e.g. /user/1234/profile)
  -l   file of target URLs, one per line
  -b   B's own equivalent resource URL for baseline comparison
  -L   file of B's baseline URLs, aligned line-by-line with -l

v2.0 options:
  -m   HTTP method: GET (default), POST, PUT, DELETE, PATCH
  -d   request body (for POST/PUT/PATCH)
  -T   content-type for request body (default: application/json)
  -e   ID enumeration range, e.g. 1-100 (use {ID} in -u URL template)
  -t   number of threads (default: 4, use 1 for sequential)
  -r   rate limit: max requests per second (default: unlimited)
  -f   report format: text (default), json, html
  -c   load options from config file
  -C   disable colored output

General options:
  -o   write report to file instead of stdout
  -v   verbose: include response body previews and header analysis
  -h   show this help message
```

## Examples with Output

### Example 1: Detecting IDOR (Vulnerable Endpoint)
```bash
./idor_prober -A test/sessionA.txt -B test/sessionB.txt \
  -u 'http://127.0.0.1:8899/user/1001/profile' \
  -b 'http://127.0.0.1:8899/user/2002/profile' -v -C
```

Output:
```
idor_prober v2.0 report
Method: GET | Threads: 4 | Rate limit: unlimited
Authorized security testing only.

[!!] IDOR CONFIRMED: http://127.0.0.1:8899/user/1001/profile [GET] (confidence 100%)
================================================================
TARGET: http://127.0.0.1:8899/user/1001/profile  [GET]
  A  -> HTTP 200 (0.00s, 75 bytes)
  B  -> HTTP 200 (0.00s, 75 bytes)
  B baseline -> HTTP 200 (0.00s, 69 bytes)

  VERDICT: IDOR_CONFIRMED   (confidence: 100%)
  cross_similarity=1.00  shape=1.00  value=1.00  baseline_similarity=0.35
  reason: B's response to A's resource matches A's data (shape=1.00, value=1.00) and does not match B's own baseline.

  [Header Analysis]
  Missing security headers: X-Content-Type-Options, X-Frame-Options, Strict-Transport-Security, Content-Security-Policy, X-XSS-Protection, Cache-Control
  Cache concern: Cache-Control missing, potential cache leak.

  [A body]        {"id": 1001, "name": "Alice", "email": "alice@corp.com", "balance": 4200.5}
  [B cross body]  {"id": 1001, "name": "Alice", "email": "alice@corp.com", "balance": 4200.5}
  [B own body]    {"id": 2002, "name": "Bob", "email": "bob@corp.com", "balance": 10.0}

==================================================================
                      SCAN SUMMARY
==================================================================
  Total targets scanned: 1
  IDOR CONFIRMED:        1
  DENIED (safe):         0
  Safe (remapped):       0
  Ambiguous:             0
  Not JSON:              0
==================================================================
```

### Example 2: Safe Endpoint (Access Denied)
```bash
./idor_prober -A test/sessionA.txt -B test/sessionB.txt \
  -u 'http://127.0.0.1:8899/safe/1001/profile' -C
```

Output:
```
idor_prober v2.0 report
Method: GET | Threads: 4 | Rate limit: unlimited
Authorized security testing only.

================================================================
TARGET: http://127.0.0.1:8899/safe/1001/profile  [GET]
  A  -> HTTP 200 (0.00s, 75 bytes)
  B  -> HTTP 403 (0.00s, 26 bytes)

  VERDICT: DENIED   (confidence: 90%)
  cross_similarity=0.00  shape=0.00  value=0.00  baseline_similarity=n/a
  reason: HTTP 403 returned for cross-account request -- access control rejected the request at the transport layer.

==================================================================
                      SCAN SUMMARY
==================================================================
  Total targets scanned: 1
  IDOR CONFIRMED:        0
  DENIED (safe):         1
  Safe (remapped):       0
  Ambiguous:             0
  Not JSON:              0
==================================================================
```

### Example 3: POST Method IDOR
```bash
./idor_prober -A test/sessionA.txt -B test/sessionB.txt \
  -u 'http://127.0.0.1:8899/api/v1/users/1001/settings' \
  -m POST -d '{"theme":"dark"}' -v -C
```

Output:
```
idor_prober v2.0 report
Method: POST | Threads: 4 | Rate limit: unlimited
Authorized security testing only.

[!!] IDOR CONFIRMED: http://127.0.0.1:8899/api/v1/users/1001/settings [POST] (confidence 100%)
================================================================
TARGET: http://127.0.0.1:8899/api/v1/users/1001/settings  [POST]
  A  -> HTTP 200 (0.00s, 164 bytes)
  B  -> HTTP 200 (0.00s, 164 bytes)

  VERDICT: IDOR_CONFIRMED   (confidence: 100%)
  cross_similarity=1.00  shape=1.00  value=1.00  baseline_similarity=n/a
  reason: B's response to A's resource matches A's data (shape=1.00, value=1.00) and does not match B's own baseline (baseline not tested).

  [A body]        {"status": "success", "message": "Settings updated for user 1001", "settings": {"theme": "dark", "notifications": true, "email_alerts": true, "privacy": "private"}}
  [B cross body]  {"status": "success", "message": "Settings updated for user 1001", "settings": {"theme": "dark", "notifications": true, "email_alerts": true, "privacy": "private"}}

==================================================================
                      SCAN SUMMARY
==================================================================
  Total targets scanned: 1
  IDOR CONFIRMED:        1
  DENIED (safe):         0
  Safe (remapped):       0
  Ambiguous:             0
  Not JSON:              0
==================================================================
```

### Example 4: ID Enumeration with JSON Output
```bash
./idor_prober -A test/sessionA.txt -B test/sessionB.txt \
  -u 'http://127.0.0.1:8899/user/{ID}/profile' \
  -e 1001-1003 -f json -C -t 2
```

Output:
```json
{
  "idor_prober_version": "2.0",
  "summary": {
    "total": 3,
    "idor_confirmed": 3,
    "denied": 0,
    "safe_remapped": 0,
    "ambiguous": 0,
    "not_json": 0
  },
  "results": [
    {
      "url": "http://127.0.0.1:8899/user/1001/profile",
      "method": "GET",
      "verdict": "IDOR_CONFIRMED",
      "confidence": 100,
      "status_a": 200,
      "status_b_cross": 200,
      "cross_similarity": 1.0000,
      "shape_similarity": 1.0000,
      "value_similarity": 1.0000,
      "baseline_similarity": null,
      "reason": "B's response to A's resource matches A's data (shape=1.00, value=1.00) and does not match B's own baseline (baseline not tested)."
    }
  ]
}
```

### Example 5: Batch Scan with Multiple Verdict Types
```bash
./idor_prober -A test/sessionA.txt -B test/sessionB.txt -l test/urls.txt -t 4 -C
```

Output (summary only):
```
==================================================================
                      SCAN SUMMARY
==================================================================
  Total targets scanned: 6
  IDOR CONFIRMED:        3
  DENIED (safe):         2
  Safe (remapped):       0
  Ambiguous:             0
  Not JSON:              1
==================================================================
```

## Real-World Bug Bounty Test Plan

### Step 1: Preparation
- Create two test accounts on the target platform
- Extract session tokens from browser DevTools (Network tab)
- Create session files with Cookie/Authorization/Header directives

### Step 2: Reconnaissance
- Use Burp Suite proxy to capture all API endpoints while browsing
- Look for URLs with user IDs, object IDs, UUIDs
- Common patterns to look for: /api/v1/users/{id}/, /api/orders/{id}, /api/documents/{uuid}
- Save all endpoints in a urls.txt file

### Step 3: Initial Scan
- Start with GET requests at low rate: ./idor_prober -A a.txt -B b.txt -l urls.txt -r 5 -v
- Review results, filter IDOR_CONFIRMED

### Step 4: Deep Testing
- Test write endpoints: -m POST, -m PUT, -m DELETE
- Enumerate IDs: -e 1-500 with {ID} template
- Use baseline URLs: -b for accurate detection

### Step 5: Report Generation
- Generate HTML report: -f html -o report.html
- Generate JSON for automation: -f json -o report.json
- Filter with jq: cat report.json | jq '.results[] | select(.verdict == "IDOR_CONFIRMED")'

### Step 6: Bug Bounty Submission Tips
- Document the vulnerability with steps to reproduce
- Include the HTML report as evidence
- Explain the impact (data exposure, unauthorized modification)
- Rate write-based IDOR higher than read-based

### Safety and Rate Limiting Tips
- Always use -r flag on real targets (start with 5 req/s)
- Only test targets in scope of the bug bounty program
- Keep threads low on production targets (-t 2 or -t 4)
- Check the program's rate limiting policies first

## Verdicts Explained
| Verdict | Meaning | Action |
|---------|---------|--------|
| IDOR_CONFIRMED | User B received User A's data | Report immediately |
| DENIED | Server returned 401/403 | Endpoint is properly protected |
| SAFE_REMAPPED | B got 200 but received B's own data | Server correctly scoped the request |
| AMBIGUOUS | Inconclusive result | Manual verification needed |
| NOT_JSON | Response is not JSON | Check manually, could be file download IDOR |

## Config File Format
The scanner supports a key=value configuration file:
```ini
session_a=test/sessionA.txt
session_b=test/sessionB.txt
method=GET
threads=4
rate_limit=10
format=json
verbose=true
color=false
```

## Testing with Mock Server
You can test the tool safely using the included mock server:
```bash
python3 test/mock_server.py &
./idor_prober -A test/sessionA.txt -B test/sessionB.txt -u 'http://127.0.0.1:8899/user/1001/profile' -v
```

Mock server endpoints:
- /user/{id}/profile (GET) - Vulnerable to IDOR
- /api/v1/users/{id}/settings (POST) - Vulnerable to IDOR
- /safe/{id}/profile (GET) - Returns 403 (Protected)
- /remapped/{id}/profile (GET) - Returns caller's own profile (Safe)
- /download/{id}/report (GET) - Non-JSON response

## Architecture
- http_client: libcurl wrapper with multi-method support
- json_diff: JSON structural diffing engine
- reporter: multi-format report generation
- thread_pool: pthreads-based concurrent execution
- rate_limit: token-bucket rate limiter
- header_analysis: security header auditing
- config: configuration file parser

## License
MIT License

## Disclaimer
This tool is for authorized security testing only. Only use against systems you own or have explicit written permission to test. Unauthorized access to computer systems is illegal.

## Author
Venu-exe
