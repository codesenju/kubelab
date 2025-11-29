````markdown

# NVMe Support on Dell OptiPlex (Service Tag: BM9NW14)

## Summary & Technical Notes

This document explains why your Dell OptiPlex cannot use an NVMe SSD in the M.2 A/E slot and outlines the correct alternatives for internal NVMe usage.

---

# Summary

- The Dell OptiPlex (Service Tag: **BM9NW14**) includes an **M.2 KEY-E slot**, intended **only for WiFi/Bluetooth cards**.
- This slot lacks PCIe ×4 NVMe lanes → **cannot support NVMe SSDs**, even with an adapter.
- Your NVMe SSD **can only work**:
  - In the **existing M.2 KEY-M NVMe slot** (already used by your system drive), or  
  - Through a **PCIe ×4 / ×16 → M.2 NVMe adapter card**
- USB enclosures work only as external USB mass storage, not direct PCIe NVMe passthrough.

---

# Full Documentation (Markdown)

## 1. Overview

This document provides technical clarification on NVMe SSD compatibility for the Dell OptiPlex system identified by Service Tag **BM9NW14**. It explains which M.2 slots support NVMe, why some adapters will not work, and what upgrade paths are recommended.

---

## 2. Hardware Summary

Your OptiPlex motherboard includes:

| Slot Type | Key | Supported Device | NVMe Support |
|----------|------|------------------|---------------|
| **M.2 Slot 1** | KEY-M | NVMe SSD | **YES** |
| **M.2 Slot 2** | KEY-E | WiFi/BT (2230) | **NO** |
| **PCIe x16 Slot** | – | GPUs, NVMe Adapter | **YES** |
| **PCIe x4/x1 Slot** | – | NICs, NVMe Adapter | **YES** |

---

## 3. Why the M.2 KEY-E Slot Cannot Use NVMe

The **M.2 KEY-E** slot only provides:

- PCIe ×1 lanes  
- USB 2.0  
- CNVi for Intel wireless cards  

It **does not provide PCIe ×4 lanes**, which are required for NVMe SSDs.

Even if you install:

- **M.2 A/E → M.2 M adapters**
- **WiFi slot → NVMe adapters**

Your SSD will **not enumerate** and will never appear in:

```
lsblk
lspci
dmesg
```

---

## 4. What Works with NVMe in This System

### 4.1 Existing NVMe Slot (KEY-M)
Your OS disk (`nvme0n1`) already uses this.

### 4.2 Using NVMe Through PCIe Adapter (Recommended)

Install an adapter card:

```
PCIe x4 → NVMe M.2 (KEY-M)
```

Then the SSD will appear as:

```
/dev/nvme1n1
```

This method supports:

- Proxmox PCIe passthrough  
- TrueNAS ZFS pools  
- L2ARC / SLOG ZIL usage  
- Full NVMe performance  

---

## 5. What Does NOT Work

- M.2 A/E slot adapters  
- WiFi slot NVMe adapters  
- Attempting to force NVMe into a WiFi slot  

Your system will never detect the drive this way.

---

## 6. Using the NVMe USB Enclosure

Your RTL9210 NVMe USB enclosure appears as a **USB mass storage device**, not NVMe PCIe hardware.

Example:

```
/dev/sda
usb-Realtek_RTL9210_NVME_*
```

You can use it for:

- Backup  
- Importing data  
- Expanding TrueNAS pools via USB (not recommended for ZFS long-term)

But **you cannot passthrough NVMe natively** via USB.

---

## 7. Recommended Solution

### Use a PCIe NVMe Adapter Card

Install your NVMe SSD into:

- **PCIe ×4 slot** → recommended  
- **PCIe ×16 slot** → also works  

This restores full NVMe PCIe interface support.

Then in Proxmox:

```bash
qm set 102 --hostpci0 0000:03:00.0
```

(PCIe device address depends on the slot used.)

---

## 8. Live Commands / Evidence

The following are actual command outputs captured from `kubelab-1` showing the VM list, USB device identification, and disk-by-id entries. These are provided as provenance for the diagnostics above.

```
root@kubelab-1:~# qm list
      VMID NAME                 STATUS     MEM(MB)    BOOTDISK(GB) PID
       101 win11                stopped    4096              64.00 0
       102 TrueNAS              running    8192              20.00 991475
      2001 ubuntu               running    10240             80.00 1888
      4000 k8s-lb               running    1024              20.00 1965
      4001 k8s-control-plane-1  running    6144              30.00 2041
      4002 k8s-control-plane-2  running    6144              30.00 2102
      5001 k8s-worker-1         running    16384             80.00 2188
      5002 k8s-worker-2         running    16384             80.00 2261
root@kubelab-1:~# lsusb -v -d 0bda:9210 | grep -i bcdDevice
  bcdDevice           f0.01
root@kubelab-1:~# ls -l /dev/disk/by-id/ | grep RTL9210
lrwxrwxrwx 1 root root  9 Nov 29 11:29 usb-Realtek_RTL9210_NVME_012345679989-0:0 -> ../../sda
lrwxrwxrwx 1 root root 10 Nov 29 11:29 usb-Realtek_RTL9210_NVME_012345679989-0:0-part1 -> ../../sda1
root@kubelab-1:~# qm set 102 -scsi2 /dev/disk/by-id/usb-Realtek_RTL9210_NVME_012345679989-0:0
update VM 102: -scsi2 /dev/disk/by-id/usb-Realtek_RTL9210_NVME_012345679989-0:0
```

---

## 9. Conclusion

Your Dell OptiPlex does **not** allow NVMe in the M.2 A/E (WiFi) slot due to electrical lane limitations.  
To use an internal NVMe drive, a **PCIe → NVMe adapter** is the correct and fully supported method.


````

*** End Patch