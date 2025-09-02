#! /usr/bin/env python3
# -*- python -*-
# -*- coding: utf-8 -*-

import subprocess
import os
import sys
test_output =  '''
'''

def run_shell_cmd(cmd, exit_on_error=True, debug=False):
    result = subprocess.run(cmd,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            shell=True)
    ret = (result.returncode == 0)

    stderr = result.stderr.decode("utf-8")
    stdout = result.stdout.decode("utf-8")

    if debug:
        print(f"Running command [ {cmd} ]")
        print("----Stderr----:\n", stderr)
        print("----Stdout----:\n", stdout)

    if exit_on_error and ret is False:
        print(f"Fail to executing cmd [{cmd}]")
        print(stderr, file=sys.stderr)
        sys.exit(1)

    return ret, stdout, stderr



class_code_net_controller = "02"
class_code_storage_controller = "01"

pci_class_name_table = {
    "0107": "Serial Attached SCSI controller",
    "0200": "Ethernet controller",
    "0106": "SATA controller",
    '0108': 'Non-Volatile memory controller',
    "0100": "SCSI storage controller",
    # '0c03': 'USB controller',
}

def parse_str_mul_line_kv(content: str, key_translate_table=None, delimiter=':'):
    """
    parse string that contains multi lines, each line format looks like:
    "key:           value"
    The line will be formatted to python dict {@key: @value}
    Sometimes, @key needs to be translated to @SOME_OTHER_KEY,
    pass {@key: @SOME_OTHER_KEY} throught key_translate_table
    if SOME_OTHER_KEY is None, @key will be used to store in @ret_dict
    """
    ret_dict = {}
    for line in content.splitlines(keepends=False):
        if len(line) == 0 or delimiter not in line:
            continue
        line_split = line.partition(delimiter)
        # Slot: 18:00.0 ===> key = "Slot" value = "18:00.0"
        if len(line_split) != 3:
            continue
        key, value = line_split[0].strip(), line_split[2].strip()
        if key_translate_table is not None:
            if key in key_translate_table:
                if key_translate_table[key]:
                    ret_dict[key_translate_table[key]] = value
                else:
                    ret_dict[key] = value
            else:
                continue
        else:
            ret_dict[key] = value
    return ret_dict

class PciDevInfo:
    @property
    def driver(self):
        driver_file = f"/sys/bus/pci/devices/{self.dbdf}/driver"
        if os.path.islink(driver_file):
            driver = os.path.basename(os.readlink(driver_file))
            return driver

        return "none"

    def __init__(self, dbdf:str):
        self.pci_class = str()
        self.vendor_id = str()
        self.device_id = str()
        self.sub_vendor_id = str()
        self.sub_device_id = str()
        self.rev = str()
        self.numa_node = str()
        self.prog_interface = str()
        self.phy_slot = str()
        self.class_str = str()
        self.vendor_str = str()
        self.device_str = str()
        self.sub_vendor_str = str()
        self.sub_device_str = str()
        self.scsi_host = []
        self.eth_nic = str()

        self.domain = dbdf
        self.bdf = dbdf[dbdf.find(":"):]
        self.dbdf = dbdf

        if not dbdf:
            return

        cmd = f"lspci -vmm -n -s {self.dbdf}"

        _, stdout, _ = run_shell_cmd(cmd)
        # output example:
        """
        [root@n-67-88 15:06:28 ~]$lspci  -vmm  -n  -s 18:00.0                  
        Slot:   18:00.0
        Class:  0107
        Vendor: 1000
        Device: 0097
        SVendor:        1028
        SDevice:        1f45
        Rev:    02
        NUMANode:       0
        """
        key_key_translate_table = {
            "Slot": "bdf",
            "Class": "pci_class",
            "Vendor": "vendor_id",
            "Device": "device_id",
            "SVendor": "sub_vendor_id",
            "SDevice": "sub_device_id",
            "Rev": "rev",
            "NUMANode": "numa_node",
            "ProgIf": "prog_interface",
            "PhySlot": "phy_slot",
        }
        pci_dev_info = parse_str_mul_line_kv(stdout, key_key_translate_table)
        self.__dict__.update(pci_dev_info)

        # we need some description
        cmd = f"lspci -vmm -s {self.bdf}"
        _, stdout, _ = run_shell_cmd(cmd)
        # output looks like
        """
        Slot:   00:0c.0
        Class:  Unclassified device [00ff]
        Vendor: Red Hat, Inc.
        Device: Virtio memory balloon
        SVendor:        Red Hat, Inc.
        SDevice:        Virtio memory balloon
        PhySlot:        12
        """
        key_key_translate_table = {
            "Class": "class_str",
            "Vendor": "vendor_str",
            "Device": "device_str",
            "SVendor": "sub_vendor_str",
            "SDevice": "sub_device_str",
        }
        pci_dev_info = parse_str_mul_line_kv(stdout, key_key_translate_table)
        self.__dict__.update(pci_dev_info)


        if self.pci_class.startswith(class_code_storage_controller):
            scsi_host_path = "/sys/class/scsi_host"

            # dev_path = os.path.join("/sys/bus/pci/devices/", bdf)
            with os.scandir(scsi_host_path) as entries:
                for entry in entries:
                    if not os.path.islink(entry.path):
                        continue
                    phy_dev_path = os.readlink(entry.path)
                    if self.bdf in phy_dev_path:
                        # print(f"{self.bdf}", entry.name, f"driver: {self.driver}")
                        self.scsi_host.append(entry.name)
        elif self.pci_class.startswith(class_code_net_controller):
            net_class_dev_path = "/sys/class/net"

            # dev_path = os.path.join("/sys/bus/pci/devices/", bdf)
            with os.scandir(net_class_dev_path) as entries:
                for entry in entries:
                    if not os.path.islink(entry.path):
                        continue
                    phy_dev_path = os.readlink(entry.path)
                    if self.bdf in phy_dev_path:
                        # print(f"{self.bdf}", entry.name, f"driver: {self.driver}")
                        self.eth_nic = entry.name
                        break
    def is_vf(self):
        physfn = f"/sys/bus/pci/devices/{self.dbdf}/physfn"
        return os.path.exists(physfn)

    def get_vf_list(self):
        ret_list = []
        sriov_numvfs_path = f"/sys/bus/pci/devices/{self.dbdf}/sriov_numvfs"
        if not os.path.exists(sriov_numvfs_path):
            return ret_list
        with open(sriov_numvfs_path, 'r') as f:
            num_vfs = int(f.read())

        for vf_soft_link in [ "virtfn{}".format(i) for i in range(0, num_vfs) ]:
            _path = f"/sys/bus/pci/devices/{self.dbdf}/{vf_soft_link}"
            _link = os.readlink(_path)
            ret_list.append(os.path.basename(_link))
        return ret_list

class Pci:
    @classmethod
    def get_pci_dev_list(cls, class_filter:str, only_pf:bool):
        pci_dev_list = []
        if class_filter == "storage":
            class_filter_list = [class_code_storage_controller]
        elif class_filter == "nic":
            class_filter_list = [class_code_net_controller]
        else:
            class_filter_list = [class_code_storage_controller, class_code_net_controller]
        _, output, _ = run_shell_cmd("lspci -D -n")
        for line in output.splitlines():
            fields = line.split()
            dbdf = fields[0]
            class_code = fields[1].rstrip(":")

            if class_code[:2] not in class_filter_list:
                continue

            pdev = PciDevInfo(dbdf=dbdf)
            if only_pf and pdev.is_vf():
                continue
            pci_dev_list.append(pdev)
        return pci_dev_list


class Mod:
    def __init__(self, name:str):
        self.name = name
        self.version = "unknown" 
        version_path = os.path.join("/sys/module/", self.name, "version")
        try:
            with open(version_path) as f:
                self.version = f.read().strip()
        except:
            pass
            

def main():
    pci_dev_list = Pci.get_pci_dev_list("storage", only_pf=True)
    print("{:^16}{:^32}{:^16}".format("SLOT", "DRIVER", "SCSI_Host"))
    for d in pci_dev_list:
        driver_version = Mod(d.driver).version
        driver_string = f"{d.driver}({driver_version})"
        print("{:<16}{:<32}{}".format(d.dbdf, driver_string, str(d.scsi_host)))

    print("")
    pci_dev_list = Pci.get_pci_dev_list("nic", only_pf=True)
    print("{:^16}{:^32}{:^16}".format("SLOT", "DRIVER", "ETH_NIC"))
    for d in pci_dev_list:
        driver_version = Mod(d.driver).version
        driver_string = f"{d.driver}({driver_version})"
        print("{:<16}{:<32}{}".format(d.dbdf, driver_string, d.eth_nic))
        for vf in d.get_vf_list():
            pci_vf_dev = PciDevInfo(vf)
            driver_version = Mod(pci_vf_dev.driver).version
            driver_string = f"{pci_vf_dev.driver}({driver_version})"
            print("  {:<14}  {:<32}{}".format(
                pci_vf_dev.dbdf, driver_string, pci_vf_dev.eth_nic))


if __name__ == "__main__":
    main()
