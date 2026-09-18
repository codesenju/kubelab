## Vega
```bash
export PROXMOX_VE_USERNAME=User@pam
export PROXMOX_VE_ENDPOINT=https://pve.mydomain.com
export PROXMOX_VE_PASSWORD='***'
```
```bash
tofu init --backend-config vega.s3.tfbackend --upgrade
tofu plan -var-file=vega.tfvars -out=out.tfplan
tofu apply "out.tfplan"    
```
