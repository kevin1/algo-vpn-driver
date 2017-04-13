#!/bin/bash

set -e

# Cloud-init script for noninteractive installation of Algo
# Please set your cloud provider toward the end of the script.

# Test an IP address for validity:
# Usage:
#      valid_ip IP_ADDRESS
#      if [[ $? -eq 0 ]]; then echo good; else echo bad; fi
#   OR
#      if valid_ip IP_ADDRESS; then echo good; else echo bad; fi
#
# Source: http://www.linuxjournal.com/content/validating-ip-address-bash-script
function valid_ip()
{
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

# not available during cloud-init
export HOME="/root"

apt update
apt upgrade -y
# install algo dependencies
apt install -y python-setuptools build-essential libssl-dev libffi-dev python-dev
# install my packages
apt install -y htop iftop sl

cd /root
git clone https://github.com/trailofbits/algo.git
cd algo
# People keep breaking algo and I know this commit was stable
git checkout 2798f84d3fdbaf8289ebbe9ec384a266d8ad4b1d

easy_install pip
pip install -r requirements.txt

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
  "#----------------------------------------------------------------------#"

additional_information: |
  "#----------------------------------------------------------------------#"
  "#      Shell access: ssh -i {{ ansible_ssh_private_key_file }} {{ ansible_ssh_user }}@{{ ansible_ssh_host }}        #"
  "#----------------------------------------------------------------------#"


SSH_keys:
  comment: algo@ssh
  private: configs/algo.pem
  public: configs/algo.pem.pub
END

google="curl --silent http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip -H \"Metadata-Flavor: Google\""
digitalocean="curl --silent http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address"
aws="curl --silent http://instance-data/latest/meta-data/public-ipv4"
declare -a cmds=("$digitalocean" "$aws" "$google")
nr_cmds=${#cmds[@]}
for (( i=0; i<${nr_cmds}; i++ )); do
    set +e
    ip=$(eval "${cmds[$i]}")
    if [ $? -eq 0 ] && valid_ip "$ip"; then
        echo "$ip"
        break
    fi
    set -e
done

# Set up VPN and SSH tunneling accounts on the local machine
# Also, apply security enhancements
tags='local vpn ssh_tunneling security'

# In the algo driver script, these tags are always skipped
skip_tags='_null encrypted'

# Since we already know the public IP
skip_tags="$skip_tags cloud update-alternatives"

options=''
# Since we're installing on local machine
options="$options server_ip=localhost server_user=`whoami`"

# Find our IP address using a cloud data service. Required for certificates.
ip=$(eval "$digitalocean")
options="$options IP_subject_alt_name=$ip"

# Causes the vpn role to generate a .mobileconfig for installing the client
# certificate on Apple devices.
# Can optionally pass "OnDemandEnabled_WIFI_EXCLUDE=\"A,B,C\"" to disconnect the
# VPN upon connecting to networks named A, B, or C.
options="$options OnDemandEnabled_WIFI=Y"
options="$options OnDemandEnabled_WIFI_EXCLUDE=\"\""
options="$options OnDemandEnabled_Cellular=Y"

tags="${tags// /,}"
skip_tags="${skip_tags// /,}"

echo "Running with args: -t $tags -e $options --skip-tags $skip_tags"
ansible-playbook deploy.yml -t "$tags" -e "$options" --skip-tags "$skip_tags"

# Private keys are world readable by default :(
chmod 600 configs/*
