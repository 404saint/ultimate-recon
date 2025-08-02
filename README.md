# 🕵️‍♂️ Ultimate Recon Tool (v1.0)

Single Bash script for **full network reconnaissance** in lab environments.  
Choose your recon mode or go **God Mode** for maximum intel.

> ⚠️ **Disclaimer:** Lab use only. Run only on networks you are authorized to test.

---

## ✨ Features

- **Wi-Fi Recon** with `airodump-ng` (monitor mode)
- **Subnet Discovery** with `arp-scan` & `fping`
- **Nmap Scanning**: Fast or Full (with service & OS detection)
- **Service Fingerprinting** with `whatweb`, `whois`, and banner grabbing
- **Passive Traffic Sniffing** with `tcpdump`
- **Markdown Summary Report** and clean, color-coded logs
- **God Mode**: Runs all recon steps in sequence

---

## 🛠️ Installation

```bash
git clone https://github.com/404saint/ultimate-recon.git
cd ultimate-recon
chmod +x ultimate_recon.sh
```

---

## Make sure required tools are installed:

```bash
sudo apt install nmap arp-scan aircrack-ng whatweb whois tcpdump fping -y
```

---

## 🚀 Usage

```bash
sudo ./ultimate_recon.sh
