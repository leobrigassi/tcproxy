#!/bin/bash
# shellcheck shell=bash
# tcproxy — one-shot VM provisioning, run during --install after the VM
# boots for the first time. Writes root's passwd, /etc/fstab entries for
# each configured Time Capsule share, the matching /etc/samba/smb.conf
# stanzas, restarts samba, and replaces /etc/motd.
# Depends on: lib/config.sh (TCPROXY_VM_SSH_PORT), lib/common.sh
#             (logm, logsm, logsc).

# Runs on the host; every step is an ssh one-liner to the VM.
# Preserves the original nested-heredoc / quoting style verbatim —
# shellcheck complains at many of these lines, but changing the quoting
# subtly breaks passwords containing special characters, which is why
# the original accepted the lint noise.
# shellcheck disable=SC2086,SC2027,SC2016
provision_VM() {
    TC_FSTAB_USER=$(if [ -z "$TC_USER" ]; then echo ""; else echo ",username=$TC_USER"; fi)
    logm "Provisioning VM..."
    logsm "Configuring VM root passwd, /etc/fstab, samba"
    logsc $SUDOREQUIRED ssh root@localhost -i ./id_rsa_vm -o StrictHostKeyChecking=no -p"$TCPROXY_VM_SSH_PORT" 'echo -e "'$TC_PASSWORD'\n'$TC_PASSWORD'" | passwd' >/dev/null 2>&1
    logsc $SUDOREQUIRED ssh root@localhost -i ./id_rsa_vm -o StrictHostKeyChecking=no -p"$TCPROXY_VM_SSH_PORT" "cp /etc/fstab /etc/fstab.bak && sed '/#_Run_setup-vm-proxy-time-capsule.sh_on_host_to_edit_this_line/d' /etc/fstab.bak > /etc/fstab.new && cp /etc/fstab.new /etc/fstab"
    logsc $SUDOREQUIRED ssh root@localhost -i ./id_rsa_vm -o StrictHostKeyChecking=no -p"$TCPROXY_VM_SSH_PORT" "mkdir /mnt/tc/'$TC_USER' /mnt/tc/'$TC_DISK' /mnt/tc/'$TC_DISK_USB'"
    logsc $SUDOREQUIRED ssh root@localhost -i ./id_rsa_vm -o StrictHostKeyChecking=no -p"$TCPROXY_VM_SSH_PORT" 'sed -i "/\\[tcproxy\\]/,\$d" /etc/samba/smb.conf'
    if [[ -n $TC_DISK_USB ]]; then logsc $SUDOREQUIRED ssh root@localhost -i ./id_rsa_vm -o StrictHostKeyChecking=no -p "$TCPROXY_VM_SSH_PORT" "echo '[$TC_DISK_USB]
path = /mnt/tc/$TC_DISK_USB
browsable = yes
read only = no
force user = root' >> /etc/samba/smb.conf

"; fi
    if [[ -n $TC_USER ]]; then logsc $SUDOREQUIRED ssh root@localhost -i ./id_rsa_vm -o StrictHostKeyChecking=no -p "$TCPROXY_VM_SSH_PORT" "echo '[$TC_USER]
path = /mnt/tc/$TC_USER
browsable = yes
read only = no
force user = root' >> /etc/samba/smb.conf

"; fi
    if [[ -n $TC_DISK ]]; then logsc $SUDOREQUIRED ssh root@localhost -i ./id_rsa_vm -o StrictHostKeyChecking=no -p "$TCPROXY_VM_SSH_PORT" "echo '[$TC_DISK]
path = /mnt/tc/$TC_DISK
browsable = yes
read only = no
force user = root' >> /etc/samba/smb.conf

"; fi
    logsc $SUDOREQUIRED ssh root@localhost -i ./id_rsa_vm -o StrictHostKeyChecking=no -p "$TCPROXY_VM_SSH_PORT" "rc-service samba restart"
    if [[ -n $TC_DISK_USB ]]; then logsc $SUDOREQUIRED ssh root@localhost -i ./id_rsa_vm -o StrictHostKeyChecking=no -p"$TCPROXY_VM_SSH_PORT" 'echo "//'$TC_IP'/'$TC_DISK_USB' /mnt/tc/'$TC_DISK_USB' cifs _netdev,x-systemd.after=network-online.target'$TC_FSTAB_USER',password='$TC_PASSWORD',sec=ntlm,uid=0,vers=1.0,rw,file_mode=0777,dir_mode=0777 0 0 #_Run_setup-vm-proxy-time-capsule.sh_on_host_to_edit_this_line" | tee -a /etc/fstab.new';fi
    if [[ -n $TC_USER ]]; then logsc $SUDOREQUIRED ssh root@localhost -i ./id_rsa_vm -o StrictHostKeyChecking=no -p"$TCPROXY_VM_SSH_PORT" 'echo "//'$TC_IP'/'$TC_USER' /mnt/tc/'$TC_USER' cifs _netdev,x-systemd.after=network-online.target'$TC_FSTAB_USER',password='$TC_PASSWORD',sec=ntlm,uid=0,vers=1.0,rw,file_mode=0777,dir_mode=0777 0 0 #_Run_setup-vm-proxy-time-capsule.sh_on_host_to_edit_this_line" | tee -a /etc/fstab.new'; fi
    if [[ -n $TC_DISK ]]; then logsc $SUDOREQUIRED ssh root@localhost -i ./id_rsa_vm -o StrictHostKeyChecking=no -p"$TCPROXY_VM_SSH_PORT" 'echo "//'$TC_IP'/'$TC_DISK' /mnt/tc/'$TC_DISK' cifs _netdev,x-systemd.after=network-online.target'$TC_FSTAB_USER',password='$TC_PASSWORD',sec=ntlm,uid=0,vers=1.0,rw,file_mode=0777,dir_mode=0777 0 0 #_Run_setup-vm-proxy-time-capsule.sh_on_host_to_edit_this_line" | tee -a /etc/fstab.new'; fi
    logsc $SUDOREQUIRED ssh root@localhost -i ./id_rsa_vm -o StrictHostKeyChecking=no -p"$TCPROXY_VM_SSH_PORT" 'mv /etc/fstab.new /etc/fstab'
    logsc $SUDOREQUIRED ssh root@localhost -i ./id_rsa_vm -o StrictHostKeyChecking=no -p"$TCPROXY_VM_SSH_PORT" 'echo -e "'$TC_PASSWORD'\n'$TC_PASSWORD'" | smbpasswd -a root'
    logsc $SUDOREQUIRED ssh root@localhost -i ./id_rsa_vm -o StrictHostKeyChecking=no -p "$TCPROXY_VM_SSH_PORT" "echo '$(echo "----------------------
tcproxy: To configure the VM please [ exit ] the VM and run [ ./tcproxy -i ] from the host.

GNU tcproxy: mount Time Capsule / AirPort Extreme on debian kernels 5.15+.
For bug reports, questions, discussions and/or open issues visit:
https://github.com/leobrigassi/tcproxy
----------------------" | base64)' | base64 -d > /etc/motd"
}
