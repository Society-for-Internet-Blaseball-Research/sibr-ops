#!/usr/bin/env bash

SUDO=''
if (( $EUID != 0 )); then
    echo "Warning: Setup requires sudo perms. Continue?"

    select yn in "Yes" "No"; do
        case $yn in
            Yes ) break;;
            No ) exit;;
        esac
    done
    
    SUDO='sudo'
fi

# Install our dependencies:
# - git is used to, at minimum, clone and update our dependencies
# - autoconf is required for building argbash
# - jq is used for parsing docker configs
# - pv is good for restoring pgbackrest repos
# - curl is good

echo "Installing git, autoconf, jq, pv, and curl..."
$SUDO apt install -y git autoconf jq pv curl

echo "Installing argbash..."
# Install argbash -- very important for setting up our borg scripts!
git clone https://github.com/matejak/argbash.git
cd argbash/resources
$SUDO make install PREFIX=/usr INSTALL_COMPLETION=yes

echo "Installing borg..."
# Download and copy borg over
curl -L "https://github.com/borgbackup/borg/releases/latest/download/borg-linux64" > /usr/local/bin/borg
sudo chown root:root /usr/local/bin/borg
sudo chmod 755 /usr/local/bin/borg