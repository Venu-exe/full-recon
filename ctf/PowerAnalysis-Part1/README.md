# picoCTF — PowerAnalysis: Part 1

| Field      | Details                        |
|------------|-------------------------------|
| **CTF**    | picoCTF                        |
| **Challenge** | PowerAnalysis: Part 1       |
| **Category** | Cryptography                 |
| **Difficulty** | Hard                       |
| **Tags**   | AES, Side-Channel, CPA, SCA    |

---

## 🧠 Challenge Overview

This challenge presents a remote AES encryption oracle that leaks **power consumption traces** alongside each encryption. The goal is to recover the **secret AES key** by performing a **Correlation Power Analysis (CPA)** attack — a real-world side-channel attack used against hardware cryptographic implementations.

> The server accepts a 16-byte plaintext (in hex) and returns a power trace — a series of floating-point values representing simulated power consumption during AES encryption.

---

## 🔍 Vulnerability

**Side-Channel Attack (SCA) via Correlation Power Analysis**

AES encryption internally computes:
```
intermediate = Sbox[plaintext[i] XOR key[i]]
```

The power consumption (Hamming Weight of the intermediate value) leaks information about the key. By collecting many traces with different plaintexts and correlating them with predicted power models for each key hypothesis, we can statistically recover each key byte independently.

---

## 🛠️ Solution Approach

### Step 1 — Collect Power Traces
- Connect to the remote oracle 300 times with random 16-byte plaintexts
- Record each plaintext + corresponding power trace

### Step 2 — Correlation Power Analysis (CPA)
For each of the 16 key bytes:
1. Guess all 256 possible key byte values
2. Compute the **predicted power** for each trace using the Hamming Weight model:
   ```
   prediction = HW(Sbox[plaintext[byte_idx] XOR key_guess])
   ```
3. Compute **Pearson correlation** between predictions and each time sample across all traces
4. The key guess with the **highest maximum correlation** wins

### Step 3 — Reconstruct Flag
```
Flag: picoCTF{<recovered_16_byte_key_in_hex>}
```

---

## 📂 Files

| File | Description |
|------|-------------|
| [`picopower.py`](./picopower.py) | Full exploit script — collects traces and runs CPA attack |

---

## 🚀 Usage

```bash
# Install dependencies
pip install numpy pwntools

# Update HOST and PORT in picopower.py to match your active instance
# HOST = "saturn.picoctf.net"
# PORT = <your_port>

python3 picopower.py
```

**Expected output:**
```
[*] Collecting 300 traces from remote target...
    Collected 50/300
    Collected 100/300
    ...
[*] Performing Correlation Power Analysis...
    Recovered byte 1/16: 0x??
    Recovered byte 2/16: 0x??
    ...
[+] Success! Key found: <hex_key>
[+] Flag: picoCTF{<hex_key>}
```

---

## 📖 Key Concepts

### AES SubBytes (S-box)
The AES S-box is a non-linear substitution step. During `AddRoundKey + SubBytes`, the intermediate value `Sbox[pt[i] ^ k[i]]` is computed, and its Hamming Weight correlates with power consumption in real hardware.

### Hamming Weight Power Model
```
HW(x) = popcount(x)  # number of set bits
```
A higher Hamming Weight → more transistors switching → more power drawn.

### Pearson Correlation
```
corr(X, Y) = Cov(X,Y) / (σ_X · σ_Y)
```
A correlation close to ±1 indicates that our key guess matches the actual key byte.

### Why 300 traces?
More traces → stronger statistical signal → higher chance of correct key recovery even with noise. In practice, 200–500 traces work well for this model.

---

## 🧩 Tools & Libraries

| Tool | Purpose |
|------|---------|
| `numpy` | Efficient trace array operations & Pearson correlation |
| `pwntools` | Remote connection to the oracle server |
| `re` | Parsing the floating-point trace values from server output |

---

## 🏁 Flag Format

```
picoCTF{<16-byte AES key in hex>}
```

---

*Solved as part of picoCTF — Cryptography track.*
