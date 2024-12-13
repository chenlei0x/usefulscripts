#! /bin/bash
set -E -e -u -o pipefail
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

nic=${1:-}
ip=${2:-}
addr_mask_bits=20
dns=114.114.114.114


gateway=$(ip r | grep default | awk '{print $3}')

function usage()
{
	echo "Tools used for generating static network scripts"
	echo "$0 <nic> <static-ip>"
}

if [[ -z "$ip" ]] || [[ -z "$nic" ]]; then
	usage
	exit
fi

network_scripts_dir=/etc/sysconfig/network-scripts


ifcfg_file=$network_scripts_dir/ifcfg-$nic

if [ -e  $ifcfg_file ]; then
	if [ -e $ifcfg_file.bak ];then
		echo "$ifcfg_file.bak exists, skip back up"
	else
		echo "backing up $ifcfg_file"
		mv $ifcfg_file $ifcfg_file.bak
	fi
fi

echo "=============================="
printf "%10s : %-40s\n" ip $ip
printf "%10s : %-40s\n" mask $addr_mask_bits
printf "%10s : %-40s\n" nic $nic
printf "%10s : %-40s\n" dns $dns
printf "%10s : %-40s\n" gateway $gateway
printf "%10s : %-40s\n" ifconfig $ifcfg_file
echo "=============================="

read -p "Confirm? <y/n> " confirm

if ! [ $confirm == y ]; then
	exit
fi

cat << EOF > $ifcfg_file
TYPE=Ethernet
PROXY_METHOD=none
BROWSER_ONLY=no
BOOTPROTO=static
DEFROUTE=yes
NAME=$nic
DEVICE=$nic
ONBOOT=yes
IPADDR=$ip
PREFIX=$addr_mask_bits
DNS1=$dns
GATEWAY=$gateway
EOF

cat $ifcfg_file
ifdown $nic || true
ifup $nic

