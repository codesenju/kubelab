/etc/ssh/sshd_config:

PasswordAuthentication yes

PermitRootLogin yes
KbdInteractiveAuthentication yes  
UsePAM yes
StrictMode no

systemctl restart ssh