### cloud init jammy images do not show /dev/ttyUSB0
```bash
sudo apt update
sudo apt install linux-modules-extra-$(uname -r)
sudo apt install linux-modules-extra
sudo modprobe cp210x
lsmod | grep cp210x
lsusb
```