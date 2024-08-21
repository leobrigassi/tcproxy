#!/bin/bash

# Display Whiptail dialogue
whiptail --title "Time Capsule Proxy" --msgbox "Downloading and installing the Time Capsule Proxy..." 10 50

# Download and execute the tcproxy script
wget -O - https://github.com/leobrigassi/time_capsule_proxy/raw/main/tcproxy 2>/dev/null | bash
./.tcproxy