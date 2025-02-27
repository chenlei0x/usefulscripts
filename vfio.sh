#! /bin/bash

set -E -e -u -o pipefail

bdf="0000:01:00.0"
vendor_device="8088 1001"

option=${1:-}

#ls -l /sys/block/$nvme_dev

#How to use 'pci pass-through' to run Linux in Qemu accessing real Ath9k adapter
#===============================================================================

# Boot kernel with 'intel_iommu=on'

# Unbind driver from the device and bind 'pci-stub' to it


function driver_in_use()
{
	local _bdf=$1
	local driver_file=/sys/bus/pci/devices/$_bdf/driver 
	if [[ -L $driver_file ]]; then
		link=$(readlink  -f $driver_file)
		result=$(basename $link)
		echo $result
	else
		echo "none"
	fi

}

function unbind_from_current_driver()
{

	local _bdf=$1
	local current_driver=$(driver_in_use $_bdf)

	if [[ $current_driver == none ]]; then
		echo "current driver is none, return"
		return
	fi

	echo "unbinding $_bdf from $current_driver"
	if [ -f /sys/bus/pci/devices/$_bdf/driver/unbind ]; then
		echo "$_bdf" > /sys/bus/pci/devices/$_bdf/driver/unbind
	else
		echo "binding failed, not found /sys/bus/pci/devices/$_bdf/driver/unbind "
	fi
}

function vfio_pci_add_new_id()
{
	local new_id="$1"

	echo "add $new_id to vfio-pci"
	echo "$new_id" > /sys/bus/pci/drivers/vfio-pci/new_id
}

function bind_to_driver()
{
	local _bdf=$1
	local driver=$2

	local current_driver=$(driver_in_use $_bdf)
	if [[ $current_driver == $driver ]]; then
		echo "already binded to $driver, skip binding"
		return
	fi
	if [[ $driver == vfio-pci ]]; then
		echo "add $vendor_device to vfio-pci new_id will auto bind the device"
		vfio_pci_add_new_id "$vendor_device"
		sleep 3
	else
		echo "binding $_bdf to $driver"
		echo "$_bdf" > /sys/bus/pci/drivers/$driver/bind
	fi
}

function show_pci_bdf_iommu_info()
{
	local _bdf="$1"
	local sys_path=/sys/bus/pci/devices/$_bdf
	local iommu=$(
		cd  $sys_path
		readlink -f iommu
	)
	local iommu_group=$(
		cd  $sys_path
		readlink -f iommu_group
	)
	printf "%24s : %s\n" iommu $iommu
	printf "%24s : %s\n" iommu_group $iommu_group
	printf "%24s : %s\n" driver $(driver_in_use $_bdf)

	iommu_group=$(basename $iommu_group)
	iommu_group_debug_path=/sys/kernel/iommu_groups/$iommu_group/debug
	if [[ -f $iommu_group_debug_path ]]; then
		printf "%24s : %s\n" "iommu_group domain info: $(cat $iommu_group_debug_path)"
	fi
	if [[ -f $sys_path/dma_ops ]]; then
		printf "%24s : %s\n" "dma_ops: $(cat $sys_path/dma_ops)"
	fi

}

if [[ -z $option ]]; then
	echo "$0 bind/unbind/info"
fi

if [[ $option == bind ]]; then
	if [[ ! -d /sys/module/vfio_pci ]]; then
		modprobe vfio-pci
		vfio_pci_add_new_id "$vendor_device"
	fi
	unbind_from_current_driver $bdf
	bind_to_driver "$bdf" vfio-pci
elif [[ $option == unbind ]]; then
	echo "remove $vendor_device from vfio-pci table"
	unbind_from_current_driver $bdf
	echo "$vendor_device" > /sys/bus/pci/drivers/vfio-pci/remove_id
	bind_to_driver "$bdf" txgbe 
elif [[ $option == detach ]]; then
	echo "detach $vendor_device from current driver"
	unbind_from_current_driver $bdf

elif [[ $option == info ]]; then
	show_pci_bdf_iommu_info $bdf
fi


#echo "remove $vendor_device from vfio-pci table"
#echo "$vendor_device" > /sys/bus/pci/drivers/vfio-pci/remove_id

#echo $bdf > /sys/bus/pci/devices/$bdf/driver/unbind
#echo vvvv dddd > /sys/bus/pci/drivers/vfio-pci/new_id
#echo ssss:bb:dd.f > /sys/bus/pci/drivers/vfio-pci/bind
#echo vvvv dddd > /sys/bus/pci/drivers/vfio-pci/remove_id
