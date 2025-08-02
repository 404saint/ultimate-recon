#!/bin/bash

# ===============================
# Ultimate Recon Tool - 404saint
# Lab Use Only - Full WiFi + Subnet Recon
# ===============================

# Colors for hacker vibes
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
RESET="\e[0m"

# ASCII Banner
print_banner() {
  echo -e "${CYAN}"
  cat << "EOF"
__        ___   _ _   _       _        
\ \      / / | | | | (_)     (_)       
 \ \ /\ / /| |_| | |_ _ _ __  _  ___   
  \ V  V / |  _  | __| | '_ \| |/ _ \  
   \_/\_/  |_| |_| |_|_| | | | | (_) | 
                         |_| |_|\___/  
EOF
  echo -e "${RESET}"
}

# Globals
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_DIR="logs/$TIMESTAMP"
SUMMARY="$LOG_DIR/SUMMARY.md"
mkdir -p "$LOG_DIR"

# Root check
check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[-] This script must be run as root!${RESET}"
    exit 1
  fi
}

# Check required tools
check_tools() {
  local missing=0
  local tools=(nmap arp-scan airodump-ng whatweb whois tcpdump fping aircrack-ng)
  echo -e "${YELLOW}[i] Checking required tools...${RESET}"
  for tool in "${tools[@]}"; do
    if ! command -v "$tool" &>/dev/null; then
      echo -e "${RED}[-] Missing: $tool${RESET}"
      echo "- $tool missing" >> "$SUMMARY"
      missing=1
    else
      echo -e "${GREEN}[+] Found: $tool${RESET}"
    fi
  done
  if [[ $missing -eq 1 ]]; then
    echo -e "${RED}[-] Please install missing tools and rerun.${RESET}"
    exit 1
  fi
}

# Ask user for interface
get_interface() {
  read -rp "[?] Enter the network interface to use (e.g. wlan0, eth0): " IFACE
  # Validate interface existence
  if ! ip link show "$IFACE" &>/dev/null; then
    echo -e "${RED}[-] Interface $IFACE not found!${RESET}"
    exit 1
  fi
}

# Detect IP and subnet from interface
detect_subnet() {
  IP_ADDR=$(ip -4 addr show "$IFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
  SUBNET_MASK=$(ip -4 addr show "$IFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}/\d+' | cut -d'/' -f2)
  AUTO_SUBNET="$IP_ADDR/$SUBNET_MASK"

  echo -e "${BLUE}[i] Detected IP: $IP_ADDR${RESET}"
  echo -e "${BLUE}[i] Detected Subnet: $AUTO_SUBNET${RESET}"

  read -rp "[?] Press Enter to use this subnet or type another (CIDR): " USER_SUBNET
  SUBNET=${USER_SUBNET:-$AUTO_SUBNET}
  echo -e "${GREEN}[+] Target subnet set to: $SUBNET${RESET}"
  echo "## Target Subnet: $SUBNET" >> "$SUMMARY"
}

# Wi-Fi Recon (airodump-ng)
wifi_recon() {
  echo -e "${YELLOW}[i] Starting Wi-Fi Recon (20s scan)...${RESET}"
  # Put interface in monitor mode
  airmon-ng start "$IFACE" &>/dev/null
  MON_IFACE="${IFACE}mon"
  if ! ip link show "$MON_IFACE" &>/dev/null; then
    echo -e "${RED}[-] Failed to start monitor mode on $IFACE${RESET}"
    return 1
  fi

  AIRO_LOG="$LOG_DIR/airodump"
  timeout 20 airodump-ng "$MON_IFACE" --write "$AIRO_LOG" --output-format csv &>/dev/null
  echo -e "${GREEN}[+] Wi-Fi scan complete. Results saved.${RESET}"

  echo "## Wi-Fi Access Points" >> "$SUMMARY"
  awk -F',' '/WPA|WEP|OPN/ && !/Station MAC/ {print "- SSID: "$14" | BSSID: "$1" | Channel: "$4" | Signal: "$8" | Encryption: "$6}' "$AIRO_LOG-01.csv" >> "$SUMMARY"

  airmon-ng stop "$MON_IFACE" &>/dev/null
}

# Subnet Recon (arp-scan + fping + nmap)
subnet_recon() {
  echo -e "${YELLOW}[i] Starting Subnet Recon...${RESET}"
  echo -e "${YELLOW}[i] Running host discovery with arp-scan and fping...${RESET}"

  arp-scan --interface="$IFACE" "$SUBNET" > "$LOG_DIR/arp-scan.txt"
  fping -a -g "$(echo $SUBNET | cut -d/ -f1)/24" 2>/dev/null > "$LOG_DIR/fping.txt"

  echo "## Live Hosts" >> "$SUMMARY"
  awk '{print "- "$1}' "$LOG_DIR/fping.txt" >> "$SUMMARY"

  echo -e "${YELLOW}[i] Running fast nmap scan...${RESET}"
  nmap -T4 -F "$SUBNET" -oN "$LOG_DIR/nmap-fast.txt"

  echo -e "${YELLOW}[i] Running full nmap scan with version detection and scripts... (this will take a while)${RESET}"
  nmap -T4 -p- -A "$SUBNET" -oN "$LOG_DIR/nmap-full.txt"

  echo "## Nmap Open Ports Summary" >> "$SUMMARY"
  grep "open" "$LOG_DIR/nmap-fast.txt" | awk '{print "- Port: "$2" on Host: "$1}' >> "$SUMMARY"
}

# Service Recon (whatweb + whois + banner grabbing)
service_recon() {
  echo -e "${YELLOW}[i] Starting Service Recon on live hosts...${RESET}"

  while read -r host; do
    echo -e "${CYAN}[+] Scanning $host with WhatWeb${RESET}"
    whatweb "$host" > "$LOG_DIR/whatweb-$host.txt"
    echo "### $host" >> "$SUMMARY"
    head -n 5 "$LOG_DIR/whatweb-$host.txt" >> "$SUMMARY"

    DOMAIN=$(dig -x "$host" +short)
    if [[ -n $DOMAIN ]]; then
      whois "$DOMAIN" > "$LOG_DIR/whois-$host.txt"
      echo "- Domain: $DOMAIN" >> "$SUMMARY"
    fi

    # Banner grabbing with netcat on common ports (optional)
    for port in 80 443 22 21 3389; do
      timeout 2 bash -c "echo '' | nc -nvw 2 $host $port" &>"$LOG_DIR/banner-$host-$port.txt"
    done
  done < "$LOG_DIR/fping.txt"
}

# Passive Sniff (tcpdump)
passive_sniff() {
  echo -e "${YELLOW}[i] Capturing traffic on $IFACE for 15 seconds...${RESET}"
  tcpdump -i "$IFACE" -w "$LOG_DIR/sniff.pcap" -c 500 &>/dev/null
  echo -e "${GREEN}[+] Traffic capture saved to $LOG_DIR/sniff.pcap${RESET}"
}

# Main Menu
main_menu() {
  while true; do
    echo -e "\n${CYAN}Select Recon Mode:${RESET}"
    echo "1) Wi-Fi Recon"
    echo "2) Subnet Recon"
    echo "3) Service Recon"
    echo "4) Passive Sniff"
    echo "5) God Mode (All in sequence)"
    echo "6) Quit"
    read -rp "Choose an option (1-6): " choice

    case $choice in
      1) wifi_recon ;;
      2) subnet_recon ;;
      3) service_recon ;;
      4) passive_sniff ;;
      5)
        wifi_recon
        subnet_recon
        service_recon
        passive_sniff
        ;;
      6) echo -e "${GREEN}Goodbye!${RESET}" ; exit 0 ;;
      *) echo -e "${RED}Invalid option.${RESET}" ;;
    esac
  done
}

# ------------------------
# Script Execution Starts
# ------------------------

print_banner
check_root
check_tools
get_interface
detect_subnet
main_menu

echo -e "${GREEN}[+] Recon complete! See report at $SUMMARY${RESET}"
