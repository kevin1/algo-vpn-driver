#!/bin/bash

# Cloud-init script for noninteractive installation of Algo
# Please set your cloud provider toward the end of the script.

# not available during cloud-init
export HOME="/root"

apt update && apt upgrade
# install algo dependencies
apt install -y python-setuptools build-essential libssl-dev libffi-dev python-dev
# install my packages
apt install -y htop iftop sl

cd /root
git clone https://github.com/trailofbits/algo.git && cd algo
# People keep breaking algo and I know this commit was stable
git checkout 1483116
easy_install pip && pip install -r requirements.txt

cat <<END > config.cfg
---

# Add as many users as you want for your VPN server here
users:
  - kevin

# Add an email address to send logs if you're using auditd for monitoring.
# Avoid using '+' in your email address otherwise auditd will fail to start.
auditd_action_mail_acct: kevin@kevinchen.co

### Advanced users only below this line ###

easyrsa_dir: /opt/easy-rsa-ipsec
easyrsa_ca_expire: 3650
easyrsa_cert_expire: 3650

# If True re-init all existing certificates. (True or False)
easyrsa_reinit_existent: False

vpn_network: 10.19.48.0/24
vpn_network_ipv6: 'fd9d:bc11:4020::/48'
# https://www.sixxs.net/tools/whois/?fd9d:bc11:4020::/48
server_name: "{{ ansible_ssh_host }}"
IP_subject_alt_name: "{{ ansible_ssh_host }}"

dns_servers:
  ipv4:
    - 8.8.8.8
    - 8.8.4.4
  ipv6:
    - 2001:4860:4860::8888
    - 2001:4860:4860::8844

strongswan_enabled_plugins:
  - aes
  - gcm
  - hmac
  - kernel-netlink
  - nonce
  - openssl
  - pem
  - pgp
  - pkcs12
  - pkcs7
  - pkcs8
  - pubkey
  - random
  - revocation
  - sha2
  - socket-default
  - stroke
  - x509

ec2_vpc_nets:
  cidr_block: 172.251.0.0/23
  subnet_cidr: 172.251.1.0/24

# IP address for the proxy and the local dns resolver
local_service_ip: 172.16.0.1

pkcs12_PayloadCertificateUUID: "{{ 900000 | random | to_uuid | upper }}"
VPN_PayloadIdentifier: "{{ 800000 | random | to_uuid | upper }}"
CA_PayloadIdentifier: "{{ 700000 | random | to_uuid | upper }}"

# Block traffic between connected clients

BetweenClients_DROP: Y

congrats: |
  "#----------------------------------------------------------------------#"
  "#                          Congratulations!                            #"
  "#                     Your Algo server is running.                     #"
  "#    Config files and certificates are in the ./configs/ directory.    #"
  "#              Go to https://whoer.net/ after connecting               #"
  "#        and ensure that all your traffic passes through the VPN.      #"
  "#          Local DNS resolver and Proxy IP address: {{ local_service_ip }}         #"
  "#                     The p12 password is {{ easyrsa_p12_export_password }}                     #"
  "#                  The CA key password is {{ easyrsa_CA_password }}                 #"
  "#      Shell access: ssh -i {{ ansible_ssh_private_key_file }} {{ ansible_ssh_user }}@{{ ansible_ssh_host }}        #"
  "#----------------------------------------------------------------------#"

SSH_keys:
  comment: algo@ssh
  private: configs/algo.pem
  public: configs/algo.pem.pub
END

# desired provider (existing ubuntu server)
touch cmd
echo 5 >> cmd
# Enter IP address of your server: (use localhost for local installation)
echo localhost >> cmd
# What user should we use to login on the server? (ignore if you're deploying to localhost)
echo >> cmd
# Enter the public IP address of your server: (IMPORTANT! This IP is used to verify the certificate)
google="curl http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip -H \"Metadata-Flavor: Google\""
digitalocean="curl http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address"
aws="curl http://instance-data/latest/meta-data/public-ipv4"
echo $(eval "$digitalocean") >> cmd
# Do you want to apply security enhancements? (documented in docs/ROLES.md)
echo y >> cmd
# Do you want to install an HTTP proxy to block ads and decrease traffic usage while surfing?
echo n >> cmd
# Do you want to install a local DNS resolver to block ads while surfing?
echo n >> cmd
# Do you want to use auditd for security monitoring (see config.cfg)?
echo y >> cmd
# Do you want each user to have their own account for SSH tunneling?
echo y >> cmd
# Do you want to enable VPN always when connected to Wi-Fi?
echo n >> cmd
# Do you want to enable VPN always when connected to the cellular network?
echo n >> cmd
# Do you want to enable VPN for Windows 10 clients? (Will use insecure algorithms and ciphers)
echo n >> cmd

./algo < cmd

# Private keys are world readable by default :(
chmod 600 configs/*
