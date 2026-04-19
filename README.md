## README.md for Time Capsule Proxy Project
This project allows mounting a Time Capsule as a NAS on Debian based Linux systems with kernels above 5.15, which no longer support the `sec=ntlm` mount flag.

**Installation via script:**

Stable (main):
```
wget -O - https://github.com/leobrigassi/time_capsule_proxy/raw/main/tcproxy 2>/dev/null | bash
```

Development (dev):
```
wget -O - https://github.com/leobrigassi/time_capsule_proxy/raw/dev/tcproxy 2>/dev/null | bash
```

[Release notes and legacy versions](https://github.com/leobrigassi/time-capsule-proxy/releases)



**How it works:**
* The project runs a virtual machine (VM) using QEMU with Alpine Linux 3.13, a kernel version that supports mounting Time Capsules.
* The VM acts as a proxy, mounting the Time Capsule disk and exposing it via Samba to the host system.
* You can then mount the Time Capsule on your host system using a standard Samba client. This part is also automated via systemd after user confirmation.

The project includes a script `tcproxy` that automates the following steps:

1. Prompts you for user inputs.
2. Extracts the pre-provisioned VM image if it doesn't exist.
3. Starts the VM using qemu-system-aarch64
4. Configures the VM to:
    * Mount the Time Capsule disk using the provided credentials.
    * Set up Samba to share the mounted disk with the host system.
5. Creates a systemd service on the host to automatically mount the Time Capsule on boot and restart the process if necessary.

Follow the prompts to enter your Time Capsule credentials.
Access your files in /srv/tcproxy

To access program options type: `./tcproxy --help`


**Requirements:**

* Linux system with kernel version above 5.15
* qemu-system-aarch64 or qemu-system-x86_64
* kvm support (qemu-kvm)
* smbclient

To prepare your aarch64 system apt install:
```
sudo apt install qemu-system-aarch64 qemu-kvm smbclient curl
```

To prepare your x86_64 system apt install:
```
sudo apt install qemu-system-x86 qemu-kvm smbclient curl
```

**User Inputs:**

* **Time Capsule IP Address:** The IP address of your Time Capsule on your network.
* **Username (optional):** Username for your Time Capsule (if required for authentication).
* **Password:** Password for your Time Capsule.
* **Disk Name:** The name of the disk on your Time Capsule that you want to mount.
* **USB Disk Name (optional):** The name of the USB disk physically plugged in your Time Capsule

**Files:**

* `LICENSE`: License for the project code.
* `README.md`: This file (you are reading it now).
* `id_rsa_vm`: Private ssh key used to access the VM.
* `id_rsa_vm.pub`: Public ssh key used to access the VM.
* `qemu.mac`: MAC address of the VM.
* `data.img`: volume file of the VM.
* `uefi.rom`: uefi file required for VM boot (only aarch64).
* `tcproxy`: Script to control the VM and mounts.
* `after_tcproxy_up` if script named after_tcproxy_up exists in tcproxy folder it will be executed after tcproxy mount is successful.

**Source layout (v2.2.0+):**

End users run the single `tcproxy` file in the project root — nothing about the distribution has changed. Contributors work on the modular source instead:

```
lib/              one module per concern, each sourced by bin/tcproxy
  config.sh       constants (versions, URLs, VM ports, retries)
  common.sh       identity, paths, logging, env I/O, dep check
  ui.sh           whiptail prompts + text fallback + help menu
  server.sh       remote_log — the ONLY outbound HTTP in the code
  vm.sh           qemu lifecycle (load / stop / boot-wait / ssh)
  mount.sh        host-side cifs mount onto $TCPROXY_HOST_MOUNT_ROOT
  provision.sh    one-shot VM provisioning run during --install
  systemd.sh      boot service + health-check timer install/remove
  updater.sh      self-update and suite download
  installer.sh    install / uninstall / tcproxy_up orchestration
bin/tcproxy       argument dispatcher; sources lib/*.sh at dev time
install.sh        web-install bootstrap for wget | bash URLs
scripts/build.sh  concatenates lib/* + bin/tcproxy into ./tcproxy
```

To produce the release artifact after editing the libs:

```
./scripts/build.sh
```

This rewrites the top-level `./tcproxy` file. The script runs `bash -n`
on the output before overwriting, so a syntactically broken build can
never land in the repo root.

**Note:**

* This script modifies system files and configurations. Make sure to understand the risks involved before running it.
* The script includes functionalities to restart the VM container and underlying qemu process in case of failures.

**Getting Started:**

1. Open a terminal in the project directory.
2. Clone or download this project to your local machine.
3. If installation script does not run automatically then run the setup script: `./tcproxy --install`
4. Follow the on-screen prompts to provide the required information.
5. Wait for the script to complete the provisioning process.
6. Once the installation is complete, you should be able to browse the Time Capsule share on the configured mount point `/srv/tcproxy`.

**Additional Notes:**

* tcproxy does not phone home. No data is sent to any server during install, use, or uninstall.
* The only outbound call to our server happens when **you** run `./tcproxy --remote-log`, which uploads the last 100 log lines to help diagnose an issue you report. Nothing is sent otherwise.
* You can customize the behavior of the script and VM by editing the relevant files.
* Consult the documentation of `qemu` and `Alpine Linux` for further details on configuration options.

I hope this README.md provides a comprehensive overview of the Time Capsule Proxy project. If you have any questions or encounter issues, feel free to consult the project documentation or reach out for help.