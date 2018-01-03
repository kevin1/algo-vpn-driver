#!/bin/bash

set -e

# not available during cloud-init
export HOME="/root"
ALGO_PATH="$HOME/algo"

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

export DEBIAN_FRONTEND=noninteractive
apt update
# https://serverfault.com/a/593640/130328
apt dist-upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" --force-yes
# install algo dependencies
apt install -y python-setuptools build-essential libssl-dev libffi-dev python-dev
# install my packages
apt install -y htop iftop sl

git clone https://github.com/trailofbits/algo.git "$ALGO_PATH"
cd "$ALGO_PATH"

# Don't make users enter their p12 password when using mobileconfig
git revert --no-commit ee7264f26e07c090ce2264621ba8c8e68aea49ec

easy_install pip
pip install -r requirements.txt

# Update the configuration file
mv config.cfg config_old.cfg

# This awk script replaces any existing users with "defaultuser"
set +e
read -d '' awk_filter_users <<"EOF"
!NF      {f = 0}
f == 2   {$0 = ""}
f == 1   {$0 = "  - defaultuser"; f = 2}
/users:/ {f = 1}
1
EOF
set -e
awk "$awk_filter_users" config_old.cfg > config.cfg

# Find our IP address using a cloud data service.
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

# Required for certificates.
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
find configs/ -type d -exec chmod 700 {} \;
find configs/ -type f -exec chmod 600 {} \;
