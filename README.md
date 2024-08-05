## README.md for Time Capsule Proxy Project

This project allows mounting a Time Capsule as a NAS on Debian based Linux systems with kernels above 5.15, which no longer support the `sec=ntlm` mount flag.

**How it works:**

* The project runs a virtual machine (VM) using QEMU with Alpine Linux 3.13, a kernel version that supports mounting Time Capsules.
* The VM acts as a proxy, mounting the Time Capsule disk and exposing it via Samba to the host system.
* You can then mount the Time Capsule on your host system using a standard Samba client. This part is also automated via systemd after user confirmation.

**Requirements:**

* Linux system with kernel version above 5.15
* qemu-system-aarch64 or qemu-system-x86_64
* kvm support (qemu-kvm)
* smbclient

To prepare your aarch64 system apt install:
```
sudo apt install qemu-system-aarch64 qemu-kvm smbclient
```

To prepare your x86_64 system apt install:
```
sudo apt install qemu-system-x86_64 qemu-kvm smbclient
```

**User Inputs:**

* **Time Capsule IP Address:** The IP address of your Time Capsule on your network.
* **Disk Name:** The name of the disk on your Time Capsule that you want to mount.
* **Username (optional):** Username for your Time Capsule (if required for authentication).
* **Password:** Password for your Time Capsule.

**Installation Script:**

The project includes a script `setup-time-capsule-proxy.sh` that automates the following steps:
w
1. Prompts you for user inputs.
2. Extracts the pre-provisioned VM image if it doesn't exist.
3. Starts the VM using qemu-system-aarch64
4. Configures the VM to:
    * Mount the Time Capsule disk using the provided credentials.
    * Set up Samba to share the mounted disk with the host system.
5. Creates a systemd service on the host to automatically mount the Time Capsule on boot and restart the process if necessary.

**Installation Steps:**

Open a terminal in the destination directory. Program will create a time-capsule-proxy project folder.

Reccomended method 1: Installation via install.sh 

Run the following command:
```
wget -O - https://github.com/leobrigassi/time_capsule_proxy/raw/main/install.sh 2>/dev/null | bash && cd time-capsule-proxy 2>/dev/null ; ./setup-time-capsule-proxy.sh
```

Alternative method: Clone repository:
```
git clone https://github.com/leobrigassi/time-capsule-proxy.git
cd time-capsule-proxy
chmod +x setup-time-capsule-proxy.sh
./setup-time-capsule-proxy.sh
```
Follow the prompts to enter your Time Capsule credentials.

**Files:**

* `LICENSE`: License for the project code.
* `README.md`: This file (you are reading it now).
* `install.sh`: Script that downloads compressed archive of this repo and extracts it in time-capsule-proxy subfolder and runs `setup-time-capsule-proxy.sh` to initiate provisioning.
* `setup-time-capsule-proxy.sh`: Script to install and configure the Time Capsule proxy.
* `mount-time-capsule-proxy.sh`: Script that runs on the VM to mount the Time Capsule and start Samba.
* `timecapsule_proxy_aarch64.tar.gz`: Compressed archive containing the pre-provisioned VM image (Alpine Linux 3.13) for aarch64 architecture hosts.
* `timecapsule_proxy_x86_64.tar.gz`: Compressed archive containing the pre-provisioned VM image (Alpine Linux 3.13) for x86 architecture hosts.
* `enable_service_at_startup.sh`: Creates a systemd service file (time-capsule-proxy.service) in /etc/systemd/system that runs at startup when network is detected.
* `time-capsule-proxy.service`: This is the system service file created by `enable_service_at_startup.sh` and copied in `/etc/systemd/system`
* `id_rsa_vm`: Private ssh key used to access the VM.
* `id_rsa_vm.pub`: Public ssh key used to access the VM.
* `qemu.mac`: MAC address of the VM.
* `vm-down.sh`: Script to unmount the samba share on the host and poweroff the VM.
* `vm-restart.sh`: Script to restart the VM and remount the samba share.
* `vm-ssh.sh`: Script to SSH into the VM for debuggin purposes.

**Note:**

* This script modifies system files and configurations. Make sure to understand the risks involved before running it.
* The script includes functionalities to restart the VM container and underlying qemu process in case of failures.

**Getting Started:**

1. Open a terminal in the project directory.
2. Clone or download this project to your local machine.
3. If installation script does not run automatically then run the setup script: `setup-time-capsule-proxy.sh`
4. Follow the on-screen prompts to provide the required information.
5. Wait for the script to complete the provisioning process.

**Using the Time Capsule:**

Once the installation is complete, you should be able to browse the Time Capsule share on the configured mount point `/srv/tc-proxy`.

**Additional Notes:**

* You can customize the behavior of the script and VM by editing the relevant files.
* Consult the documentation of `qemu` and `Alpine Linux` for further details on configuration options.


I hope this README.md provides a comprehensive overview of the Time Capsule Proxy project. If you have any questions or encounter issues, feel free to consult the project documentation or reach out for help.
