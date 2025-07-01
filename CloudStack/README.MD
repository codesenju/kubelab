```yaml
#cloud-config username: cloud password: cloud
users:
  - name: cloud
    passwd: "$6$somesalt$KLY2ZQYLjdx4lBtCH.VTkiEF4xqrFa3IkhmIiNiwxjEi1N/TWcKSO8LiXTFSBlIfKjJkGtg8mNw3ZB3DYjRvj."
    lock_passwd: false
    sudo: ALL=(ALL) NOPASSWD:ALL  # Optional: Grants passwordless sudo
    shell: /bin/bash  # Sets bash as the default shell

# Ensure password doesn't expire
chpasswd:
  expire: false

# Enable password authentication for SSH
ssh_pwauth: true

# Optional: Update SSH configuration to allow password auth
write_files:
  - path: /etc/ssh/sshd_config.d/60-cloud-init.conf
    content: |
      PasswordAuthentication yes
      ChallengeResponseAuthentication no
      UsePAM yes
```

prerequisite: 
Launch VM - https://community-scripts.github.io/ProxmoxVE/scripts?id=ubuntu2404-vm
CPU=HOST

sudo apt-get install -y openjdk-8-jdk mysql-server mysql-client liblog4j1.2-java libcommons-codec-java libcommons-logging-java ant git

Enable Root Login and set root password to ubuntu

sudo apt install chrony
sudo echo "deb https://download.cloudstack.org/ubuntu focal 4.20" > /etc/apt/sources.list.d/cloudstack.list
sudo wget -O - https://download.cloudstack.org/release.asc | sudo tee /etc/apt/trusted.gpg.d/cloudstack.asc
sudo apt update
sudo apt install cloudstack-management

## install db server
sudo apt install mysql-server -y

create file /etc/mysql/conf.d/cloudstack.cnf:
[mysqld]
innodb_rollback_on_timeout=1
innodb_lock_wait_timeout=600
max_connections=350
log-bin=mysql-bin
binlog-format = 'ROW'


sudo ufw allow mysql

sudo systemctl restart mysql


```

cloudstack-setup-databases cloud:cloud@localhost --deploy-as=root -i 192.168.0.101

cloudstack-setup-management

## Prepare NFS Shares
sudo apt install nfs-kernel-server -y

sudo mkdir -p /export/primary
sudo mkdir -p /export/secondary


edit /etc/exports:

/export  *(rw,async,no_root_squash,no_subtree_check)

exportfs -a

- configure restart nfs
sed -i -e 's/^RPCMOUNTDOPTS="--manage-gids"$/RPCMOUNTDOPTS="-p 892 --manage-gids"/g' /etc/default/nfs-kernel-server
sed -i -e 's/^STATDOPTS=$/STATDOPTS="--port 662 --outgoing-port 2020"/g' /etc/default/nfs-common
echo "NEED_STATD=yes" >> /etc/default/nfs-common
sed -i -e 's/^RPCRQUOTADOPTS=$/RPCRQUOTADOPTS="-p 875"/g' /etc/default/quota
service nfs-kernel-server restart

## Network Setup
sudo apt-get install bridge-utils

comment out this file(create backup of original): /etc/netplan/50-cloud-init.yaml

create a file /etc/netplan/01-netcfg.yaml:
 network:
   version: 2
   renderer: networkd
   ethernets:
     eth0:
       dhcp4: false
       dhcp6: false
       optional: true
   bridges:
     cloudbr0:
       addresses: [192.168.0.101/24]
       routes:
        - to: default
          via: 192.168.0.1
       nameservers:
         addresses: [1.1.1.1, 8.8.8.8]
       interfaces: [eth0]
       dhcp4: false
       dhcp6: false
       parameters:
         stp: false
         forward-delay: 0


### Configure firewall
sudo ufw allow mysql
sudo ufw allow proto tcp from any to any port 22
sudo ufw allow proto tcp from any to any port 1798
sudo ufw allow proto tcp from any to any port 16509
sudo ufw allow proto tcp from any to any port 16514
sudo ufw allow proto tcp from any to any port 5900:6100
sudo ufw allow proto tcp from any to any port 49152:49216

- disable apparmour


## template


/usr/share/cloudstack-common/scripts/storage/secondary/cloud-install-sys-tmplt -m /export/secondary -u http://download.cloudstack.org/systemvm/4.17/systemvmtemplate-4.17.0-kvm.qcow2.bz2 -h kvm -F



## KVM Host
apt-get install cloudstack-agent

echo 'listen_tls = 0' >> /etc/libvirt/libvirtd.conf
echo 'listen_tcp = 1'  >> /etc/libvirt/libvirtd.conf
echo 'tcp_port = "16509"'  >> /etc/libvirt/libvirtd.conf
echo 'auth_tcp = "none"'  >> /etc/libvirt/libvirtd.conf
echo 'mdns_adv = 0'  >> /etc/libvirt/libvirtd.conf

systemctl mask libvirtd.socket libvirtd-ro.socket libvirtd-admin.socket libvirtd-tls.socket libvirtd-tcp.socket
systemctl restart libvirtd


apt-get install uuid
UUID=$(uuid)
echo host_uuid = \"$UUID\" >> /etc/libvirt/libvirtd.conf
systemctl restart libvirtd

edit /etc/cloudstack/agent/agent.properties:
guest.cpu.arch=aarch64
guest.cpu.mode=host-passthrough
host.cpu.manual.speed.mhz=1500

Launch Management Server
cloudstack-setup-management
systemctl status cloudstack-management
tail -f /var/log/cloudstack/management/management-server.log

## Check
cat /etc/libvirt/libvirtd.conf | grep -iE "auth_tcp|mdns_adv|tcp_port|listen_tcp|listen_tls"

cat /etc/mysql/conf.d/cloudstack.cnf
sudo systemctl status mysql
mysql -u root -pcloud -e "SHOW DATABASES;" | grep cloud


cat /etc/exports
showmount -e localhost
ls -ld /export/primary /export/secondary

cat /etc/default/nfs-kernel-server | grep RPCMOUNTDOPTS
cat /etc/default/nfs-common | grep -E 'STATDOPTS|NEED_STATD'
cat /etc/default/quota | grep RPCRQUOTADOPTS

cat /etc/libvirt/libvirtd.conf | grep -iE "auth_tcp|mdns_adv|tcp_port|listen_tcp|listen_tls"
cat /etc/libvirt/libvirt.conf | grep remote_mode
cat /etc/default/libvirtd | grep LIBVIRTD_ARGS

cat /etc/libvirt/libvirtd.conf | grep host_uuid

cat /etc/netplan/01-netcfg.yaml
ip a show cloudbr0
bridge link show
netstat -r

sudo iptables -L -n | grep -E '111|2049|32803|892|875|662|8250|8080|9090|16514'
sudo ufw status

cat /etc/libvirt/qemu.conf | grep -E 'vnc_listen|security_driver'

ls -l /export/secondary/template/tmpl/1/3/

systemctl status cloudstack-management cloudstack-agent libvirtd nfs-kernel-server qemu-kvm

systemctl list-unit-files | grep libvirt.*socket | grep masked

netstat -tulnp | grep java
curl -I http://localhost:8080/client
chronyc tracking

java -version

brctl show

tail -f /var/log/cloudstack/management/management-server.log
### Reference:
- https://hackmd.io/@_ZfqOpYhTCq5xfvPo9Xb8g/rkQSNa0L3