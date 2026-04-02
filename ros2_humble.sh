#!/bin/bash
# ============================================================
#  ROS2 Humble Installation Script
#  Robot  : R1 Mini
#  Target : Jetson Orin Nano Super (Ubuntu 22.04 / Jammy)
# ============================================================

set -e  # Exit immediately on any error

echo "============================================"
echo "  R1 Mini — ROS2 Humble Installer"
echo "  Target: Jetson Orin Nano Super"
echo "============================================"
echo ""

# ------------------------------------------------------------
# Step 1: Locale setup
# ------------------------------------------------------------
echo "[1/7] Setting up locale..."
sudo apt update && sudo apt install -y locales
sudo locale-gen en_US en_US.UTF-8
sudo update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
export LANG=en_US.UTF-8
echo "      Locale verification:"
locale
echo ""

# ------------------------------------------------------------
# Step 2: Enable universe repository
# ------------------------------------------------------------
echo "[2/7] Enabling universe repository..."
sudo apt install -y software-properties-common
sudo add-apt-repository universe -y
echo ""

# ------------------------------------------------------------
# Step 3: Add ROS2 APT source
# ------------------------------------------------------------
echo "[3/7] Adding ROS2 APT source..."
sudo apt update && sudo apt install -y curl

export ROS_APT_SOURCE_VERSION=$(curl -s https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest \
  | grep -F "tag_name" | awk -F'"' '{print $4}')

echo "      Using ros-apt-source version: ${ROS_APT_SOURCE_VERSION}"

curl -L -o /tmp/ros2-apt-source.deb \
  "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ROS_APT_SOURCE_VERSION}/ros2-apt-source_${ROS_APT_SOURCE_VERSION}.$(. /etc/os-release && echo ${UBUNTU_CODENAME:-${VERSION_CODENAME}})_all.deb"

sudo dpkg -i /tmp/ros2-apt-source.deb
echo ""

# ------------------------------------------------------------
# Step 4: Update & upgrade
# ------------------------------------------------------------
echo "[4/7] Updating and upgrading packages..."
sudo apt update
sudo apt upgrade -y
echo ""

# ------------------------------------------------------------
# Step 5: Install ROS2 Humble Desktop
# ------------------------------------------------------------
echo "[5/7] Installing ros-humble-desktop..."
sudo apt install -y ros-humble-desktop
echo ""

# ------------------------------------------------------------
# Step 6: Install ROS dev tools
# ------------------------------------------------------------
echo "[6/7] Installing ROS dev tools..."
sudo apt install -y ros-dev-tools
echo ""

# ------------------------------------------------------------
# Step 7: Source setup and persist in ~/.bashrc
# ------------------------------------------------------------
echo "[7/7] Sourcing ROS2 setup and adding to ~/.bashrc..."
source /opt/ros/humble/setup.bash

BASHRC_LINE="source /opt/ros/humble/setup.bash"
if ! grep -qF "${BASHRC_LINE}" ~/.bashrc; then
  echo "" >> ~/.bashrc
  echo "# ROS2 Humble — R1 Mini" >> ~/.bashrc
  echo "${BASHRC_LINE}" >> ~/.bashrc
  echo "      Added to ~/.bashrc"
else
  echo "      Already present in ~/.bashrc, skipping."
fi
echo ""

# ------------------------------------------------------------
# Done
# ------------------------------------------------------------
echo "============================================"
echo "  ROS2 Humble installation complete!"
echo "  Run the following to activate in this"
echo "  terminal session:"
echo ""
echo "    source /opt/ros/humble/setup.bash"
echo ""
echo "  Or open a new terminal — it will be"
echo "  sourced automatically via ~/.bashrc"
echo "============================================"