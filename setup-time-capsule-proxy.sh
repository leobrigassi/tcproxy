#!/bin/bash
# Time Capsule Proxy for SmallMediaHub - Updates and readme on https://github.com/leobrigassi/time-capsule-proxy

# Check system requirements
arch=$(uname -m)
if ! [[ $arch == aarch64* ]] && ! [[ $arch == x86_64* ]]; then
    echo "System not supported. Please run from x86_64 or aarch64 systems."
    exit 1
fi
if [[ $arch == x86_64* ]]; then
if ! which qemu-system-x86_64 > /dev/null; then
  echo "Qemu not detected.
  sudo apt install qemu-system-x86_64 qemu-kvm
  Please install and try again."
  exit 1
fi
fi
if [[ $arch == aarch64* ]]; then
if ! which qemu-system-aarch64 > /dev/null && ! which qemu-system-x86_64 > /dev/null; then
  echo "Qemu not _detected.
  sudo apt install qemu-system-aarch64 qemu-kvm
  Please install and try again."
  exit 1
fi
fi
if ! which smbclient >/dev/null 2>&1; then
  echo "smbclient is required for this script to work correctly. 
  sudo apt install smbclient
  Please install and try again."
  exit 1
fi

# Prompt User Inputs
read -p "[INFO] This script will install a local VM to allow mount of Time Capsule or AirPort Extreme as a NAS on linux with kernels 5.15 or above. 

Any previous setup will be OVERWRITTEN. 
Close any app or terminal window using /srv/tc-proxy before continuing. 
[INPUT] Continue? (y/N): " INSTALL
if [[ "$INSTALL" =~ ^[Yy]$ ]]; then
    echo "[  ] Installing..."
else
    echo "[INFO] Installation Aborted. No change has been performed."
    exit 1
fi

read -p "[INPUT] Time Capsule IPv4 (e.g. 192.168.1.10): " TC_IP
if [ -z "$TC_IP" ]; then
    echo "[ERROR] IPv4 required. Installation aborted"
    exit 1
fi
read -p "[INPUT] Time Capsule DISK name (e.g. Data): " TC_FOLDER
if [ -z "$TC_FOLDER" ]; then
    echo "[ERROR] DISK name is required. Installation aborted"
    exit 1
fi
read -p "[INPUT] Time Capsule USER: " TC_USER
TC_FSTAB_USER=$(if [ -z "$TC_USER" ]; then echo ""; else echo ",username=$TC_USER"; fi)
read -p "[INPUT] Time Capsule PASSWORD: " TC_PASSWORD
if [ -z "$TC_PASSWORD" ]; then
    echo "[ERROR] PASSWORD is required. Installation aborted"
    exit 1
fi

read -p "[INPUT] Do you want to enable mount at startup? (y/N): " STARTUP_MOUNT

# Define the media hub vars
TIME_CAPSULE_PROXY_PATH=$(readlink -f .)
TCP_ENV=$TIME_CAPSULE_PROXY_PATH/.env
PUID=$(id -u)
PGID=$(id -g)
TCP_SERVICE_TEMP_FILE=$TIME_CAPSULE_PROXY_PATH/time-capsule-proxy.service
TCP_SERVICE_PATH=/etc/systemd/system
TCP_SERVICE_MOUNT_FILE=$TIME_CAPSULE_PROXY_PATH/mount-time-capsule-proxy.sh

chmod +x mount-time-capsule-proxy.sh
chmod +x enable-service-at-startup.sh
chmod +x install.sh
chmod +x uninstall.sh
chmod +x vm-ssh.sh
chmod +x vm-restart.sh
chmod +x vm-down.sh

# Deflate VM
echo "[  ] Deflating VM disk..."
if [[ $arch == x86_64* ]]; then
    sudo tar -xf timecapsule_proxy_x86.tar.gz
elif [[ $arch == aarch64* ]]; then
    sudo tar -xf timecapsule_proxy_aarch64.tar.gz
fi
sudo rm timecapsule_proxy_aarch64.tar.gz
sudo rm timecapsule_proxy_x86.tar.gz

# stopping previously installed VMs and mounts
if mountpoint -q "/srv/tc-proxy"; then
    if sudo umount /srv/tc-proxy 2>/dev/null; then
        echo "[  ] Mountpoint /srv/tc-proxy detected. Unmounting..."
    else
        echo "[INFO] Cannot gracefully unmount /srv/tc-proxy. Forcing unmount..."
        sudo umount -f /srv/tc-proxy 2>/dev/null
        sleep 2
        if mountpoint -q "/srv/tc-proxy"; then
            echo "[ERROR] Cannot unmount /srv/tc-proxy. Please umount and run setup again."
            exit 1
        fi
    fi
fi
if pgrep -f "mac=02:D2:46:5B:4E:84" > /dev/null 2>&1; then
    echo "[  ] VM detected. Sending poweroff command..."
    sudo ssh root@localhost -i ./id_rsa_vm -o StrictHostKeyChecking=no -p50022 "poweroff"
    TIMEOUT=60
    INTERVAL=5
    ELAPSED=0
    while pgrep -f "mac=02:D2:46:5B:4E:84" > /dev/null 2>&1; do
        sleep $INTERVAL
        ELAPSED=$((ELAPSED + INTERVAL))
        if [ $ELAPSED -ge $TIMEOUT ]; then
            echo "[ERROR] VM did not power down after $TIMEOUT seconds. Forcing termination..."
            pkill -f "mac=02:D2:46:5B:4E:84"
            if [ $? -eq 0 ]; then
                echo "[  ] VM process killed."
            else
                echo "[ERROR] Failed to kill VM process. Installation stopped."
                break
            fi
        fi
    done
    if [ $ELAPSED -lt $TIMEOUT ]; then
        echo "[  ] VM powered down."
    fi
fi

# run VM
if [[ $arch == x86_64* ]]; then
sudo qemu-system-x86_64 \
-M q35,accel=kvm \
-cpu host \
-m 256 \
-boot order=c \
-drive file=data.img,format=qcow2,if=virtio \
-netdev user,id=net0,hostfwd=tcp::50022-:22,hostfwd=tcp::50445-:445 \
-device virtio-net,netdev=net0,mac=$(cat qemu.mac) \
-serial file:./vm.log \
-daemonize \
-display none
fi

if [[ $arch == aarch64* ]]; then
sudo qemu-system-aarch64 \
-M virt,accel=kvm \
-cpu host \
-m 256 \
-drive file=data.img,format=qcow2,if=virtio \
-bios uefi.rom \
-device virtio-net-device,netdev=net0,mac=$(cat qemu.mac) \
-netdev user,id=net0,hostfwd=tcp::50022-:22,hostfwd=tcp::50445-:445 \
-serial file:./vm.log \
-daemonize \
-display none
fi

echo "[  ] Waiting for VM to boot..."
while ! sudo tail -f ./vm.log | grep -q "Welcome to Alpine Linux"; do
 sleep 5 
done

echo "[  ] Provisioning VM..."
sleep 10
sudo ssh root@localhost -i ./id_rsa_vm -o StrictHostKeyChecking=no -p50022 'echo -e "'$TC_PASSWORD'\n'$TC_PASSWORD'" | passwd' >/dev/null 2>&1
sudo mkdir -p /srv/tc-proxy >/dev/null
chmod +x mount-time-capsule-proxy.sh >/dev/null

# Configure /etc/fstab
sudo ssh root@localhost -i ./id_rsa_vm -o StrictHostKeyChecking=no -p50022 "cp /etc/fstab /etc/fstab.bak && sed '/#_Run_setup-vm-proxy-time-capsule.sh_on_host_to_edit_this_line/d' /etc/fstab.bak > /etc/fstab.new && cp /etc/fstab.new /etc/fstab" >/dev/null 2>&1
# ssh root@localhost -i ./id_rsa_vm -o StrictHostKeyChecking=no -p50022 "cp /etc/fstab /etc/fstab.bak && cp /etc/fstab /etc/fstab.new && sed '6d' /etc/fstab.new" >/dev/null 2>&1
sudo ssh root@localhost -i ./id_rsa_vm -o StrictHostKeyChecking=no -p50022 'echo "//'$TC_IP'/'$TC_FOLDER' /mnt/tc cifs _netdev,x-systemd.after=network-online.target'$TC_FSTAB_USER',password='$TC_PASSWORD',sec=ntlm,uid=0,vers=1.0,rw,file_mode=0777,dir_mode=0777 0 0 #_Run_setup-vm-proxy-time-capsule.sh_on_host_to_edit_this_line" | tee -a /etc/fstab.new && mv /etc/fstab.new /etc/fstab' >/dev/null 2>&1
sudo ssh root@localhost -i ./id_rsa_vm -o StrictHostKeyChecking=no -p50022 'echo -e "'$TC_PASSWORD'\n'$TC_PASSWORD'" | smbpasswd -a root' >/dev/null 2>&1

# Configure mount-time-capsule-proxy.sh
if grep -q "#line_3_updated_on_first_run" < "$TCP_SERVICE_MOUNT_FILE"; then
  # Line 3 exists with the target string, delete it
sed -i 3d $TCP_SERVICE_MOUNT_FILE >/dev/null 2>&1
sed -i '3isource '$TCP_ENV' #line_3_updated_on_first_run' $TCP_SERVICE_MOUNT_FILE >/dev/null 2>&1
fi

#Save ENVs to file
if [ ! -f $TCP_ENV ]; then
    touch "$TCP_ENV"
else
    echo "# Environment variables for Time_Capsule_Proxy setup. Use Install.Time_Capsule_Proxy.sh to edit. Edit tcp.custom.env for custom variables" > $TCP_ENV
fi
echo "TIME_CAPSULE_PROXY_PATH=$TIME_CAPSULE_PROXY_PATH" >> $TCP_ENV
echo "TCP_ENV=$TCP_ENV" >> $TCP_ENV
echo "PUID=$PUID" >> $TCP_ENV
echo "PGID=$PGID" >> $TCP_ENV
echo "TC_IP=$TC_IP" >> $TCP_ENV
echo "TC_FOLDER=$TC_FOLDER" >> $TCP_ENV
echo "TC_FSTAB_USER=$TC_FSTAB_USER" >> $TCP_ENV
echo "TC_PASSWORD=$TC_PASSWORD" >> $TCP_ENV
echo "TIME_CAPSULE_PROXY_SERVICE=/etc/systemd/system/time-capsule-proxy.service" >> $TCP_ENV
echo "TCP_SERVICE_TEMP_FILE=$TCP_SERVICE_TEMP_FILE" >> $TCP_ENV
echo "TCP_SERVICE_MOUNT_FILE=$TCP_SERVICE_MOUNT_FILE" >> $TCP_ENV
echo "TCP_SERVICE_PATH=/etc/systemd/system" >> $TCP_ENV
TC_PASSWORD=""

# Test VM mount
if sudo ssh root@localhost -i ./id_rsa_vm -o StrictHostKeyChecking=no -p50022 'mount -a && mount | grep -q //'$TC_IP'/'$TC_FOLDER''
then
    echo "[  ] VM connected to Time Capsule..."
else
    echo "[ERROR] VM unable to connect to Time Capsule. Please check credentials and IPv4 and run install again."
    exit 1
fi

# Mounting samba share
echo "[  ] Initiating mounting sequence..."
touch connection.log >/dev/null 2>&1
echo "[  ] Showing logs from mount-time-capsule-proxy.sh..." > connection.log 
./mount-time-capsule-proxy.sh >/dev/null 2>&1
sleep 1
exec 2>/dev/null
tail -fq -n3 ./connection.log &
TAIL_PID=$!
STOP_STRING="System up and running"
while ! grep -q "$STOP_STRING" < ./connection.log; do
    sleep 1
done
sudo kill "$TAIL_PID" >/dev/null 2>&1
exec 2>&3

# Startup service setup
if [[ "$STARTUP_MOUNT" =~ ^[Yy]$ ]]; then
    ./enable-service-at-startup.sh
else
    echo "[INFO] run ./enable-service-at-startup.sh to enable automatic mount at startup."
    echo "[INFO] run ./mount-time-capsule-proxy.sh to mount manually"
fi

echo "[OK] Process completed"