#!/bin/bash
set -e
set -o pipefail


# === Prerequisite Check: Intel RealSense SDK ===
read -p "Prerequisite: Is Intel RealSense SDK installed? (y/n): " SDK_INSTALLED
if [[ "$SDK_INSTALLED" != "y" && "$SDK_INSTALLED" != "Y" ]]; then
    echo ""
    echo "Please install the Intel RealSense SDK first, then re-run this script."
    echo ""
    echo "Follow these instructions:"
    echo ""
    echo "  cd ~"
    echo "  git clone https://github.com/jetsonhacks/jetson-orin-librealsense.git"
    echo "  cd jetson-orin-librealsense"
    echo ""
    echo "  # Kernel modules"
    echo "  sha256sum -c install-modules.tar.gz.sha256"
    echo "  tar -xzf install-modules.tar.gz"
    echo "  cd install-modules && sudo ./install-realsense-modules.sh && cd .."
    echo "  sudo reboot"
    echo ""
    echo "  # Intel SDK (after reboot)"
    echo "  sudo mkdir -p /etc/apt/keyrings"
    echo "  curl -sSf https://librealsense.realsenseai.com/Debian/librealsenseai.asc | sudo gpg --dearmor | sudo tee /etc/apt/keyrings/librealsenseai.gpg > /dev/null"
    echo "  echo "deb [signed-by=/etc/apt/keyrings/librealsenseai.gpg] https://librealsense.realsenseai.com/Debian/apt-repo $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/librealsense.list"
    echo "  sudo apt-get update"
    echo "  sudo apt-get install -y librealsense2-utils librealsense2-dev"
    echo ""
    exit 0
fi


# === User Configuration ===
read -p "Enter robot name (e.g. r1a001): " ROBOT_NAME
read -p "Enter workspace name [default: r1_ws]: " WS_NAME
WS_NAME=${WS_NAME:-r1_ws}
WS_DIR=~/$WS_NAME
echo "  Workspace: $WS_DIR (will be created if it does not exist)"
echo ""

echo "=== [r1_mini] Starting full micro-ROS setup ==="

# Step 1: Clone micro_ros_setup if not already present
if [ ! -d "$WS_DIR/src/micro_ros_setup" ]; then
    echo "=== [1/7] Cloning micro_ros_setup ==="
    git clone -b $ROS_DISTRO \
        https://github.com/micro-ROS/micro_ros_setup.git \
        $WS_DIR/src/micro_ros_setup
else
    echo "=== [1/7] micro_ros_setup already present, skipping clone ==="
fi

cd $WS_DIR

# Step 2: rosdep install for micro_ros_setup + r1mini deps
echo "=== [2/7] Running rosdep install ==="
sudo apt update
sudo rosdep init || true
rosdep update
rosdep install --from-paths src --ignore-src --skip-keys=librealsense2 -y

# Step 3: Build micro_ros_setup
echo "=== [3/7] Building micro_ros_setup ==="
colcon build --packages-select micro_ros_setup
source $WS_DIR/install/local_setup.bash

# Step 4: Create and build the agent
echo "=== [4/7] Creating micro-ROS agent workspace ==="
ros2 run micro_ros_setup create_agent_ws.sh
echo "=== [5/7] Building micro-ROS agent ==="
ros2 run micro_ros_setup build_agent.sh

# Step 5: Clone r1_packages and drivers
echo "=== [6/7] Cloning r1_packages, IMU driver, and RPLidar driver ==="

if [ ! -d "$WS_DIR/src/r1_packages" ]; then
    git clone https://github.com/Automind-Dynamics/r1_packages.git \
        $WS_DIR/src/r1_packages
else
    echo "  r1_packages already present, skipping clone"
fi

if [ ! -d "$WS_DIR/src/ros-imu-bno055" ]; then
    git clone https://github.com/dheera/ros-imu-bno055.git \
        $WS_DIR/src/ros-imu-bno055
else
    echo "  ros-imu-bno055 already present, skipping clone"
fi

if [ ! -d "$WS_DIR/src/rplidar_ros" ]; then
    git clone -b ros2 \
        https://github.com/Slamtec/rplidar_ros.git \
        $WS_DIR/src/rplidar_ros
else
    echo "  rplidar_ros already present, skipping clone"
fi

if [ ! -d "$WS_DIR/src/realsense-ros" ]; then
    git clone -b ros2-development \
        https://github.com/realsenseai/realsense-ros.git \
        $WS_DIR/src/realsense-ros
else
    echo "  realsense-ros already present, skipping clone"
fi

# Step 9: Configure robot name in required files
echo ""
echo "=== [9/9] Configuring robot name: $ROBOT_NAME ==="
sed -i "s|/r1a001/cmd_vel|/$ROBOT_NAME/cmd_vel|g" \
    $WS_DIR/src/r1_packages/r1_teleop/launch/twist_mux_launch.py
sed -i "s|/r1a001/wheel_odom|/$ROBOT_NAME/wheel_odom|g" \
    $WS_DIR/src/r1_packages/r1_localization/config/ekf.yaml
echo "  Robot name set to '$ROBOT_NAME' in launch and config files."

# Step 6: rosdep install for newly added packages
echo "=== [6/7] Running rosdep install for new packages ==="
rosdep install --from-paths src --ignore-src --skip-keys=librealsense2 -y

# Step 7: Build
echo "=== [7/7] Building workspace ==="
source $WS_DIR/install/local_setup.bash

echo "  Building r1* packages with symlink install..."
colcon build --packages-select-regex 'r1.*' --symlink-install

echo "  Building remaining packages..."
colcon build --packages-ignore-regex 'r1.*' 'micro_ros_setup' 'micro_ros_msgs' 'micro_ros_agent'

echo ""
echo "=== [r1_mini] Setup complete! ==="
echo "Run: source $WS_DIR/install/local_setup.bash"

echo "=== [8/8] Installing udev rules ==="
sudo cp $WS_DIR/src/r1_mini/99-r1mini.rules /etc/udev/rules.d/99-r1mini.rules
sudo udevadm control --reload-rules
sudo udevadm trigger
echo "  udev rules installed and applied."

# Step 10: Install xpad joystick driver via DKMS
echo ""
echo "=== [10/10] Installing xpad joystick driver ==="
if [ ! -d ~/Downloads/xpad ]; then
    git clone https://github.com/paroj/xpad.git ~/Downloads/xpad
else
    echo "  xpad already cloned, skipping."
fi
cat > ~/Downloads/xpad/dkms.conf << 'EOF'
PACKAGE_NAME="xpad"
PACKAGE_VERSION="0.4"
CLEAN="make clean"
BUILT_MODULE_NAME[0]="xpad"
DEST_MODULE_LOCATION[0]="/kernel/drivers/input/joystick"
AUTOINSTALL="yes"
MAKE[0]="make all KVERSION=$kernelver"
EOF
sudo mkdir -p /usr/src/xpad-0.4
sudo cp -r ~/Downloads/xpad/* /usr/src/xpad-0.4/
sudo apt-get install dkms -y
sudo dkms add -m xpad -v 0.4 || true
sudo dkms build -m xpad -v 0.4
sudo dkms install -m xpad -v 0.4
sudo modprobe xpad
echo "  xpad driver installed. Joystick available at /dev/input/js0"
rm -rf ~/Downloads/xpad
echo "  Cleaned up xpad source from Downloads."

# Step 11: Install utilities
echo ""
echo "=== [11/11] Installing utilities (terminator, nano, gedit, brave, etc.) ==="
sudo apt install -y terminator nano gedit
curl -fsS https://dl.brave.com/install.sh | sh
echo "  Utilities installed."

# Step 12: Add workspace source to ~/.bashrc
echo ""
echo "=== [12/12] Adding workspace source to ~/.bashrc ==="
WS_SOURCE_LINE="source $WS_DIR/install/local_setup.bash"
if ! grep -qF "${WS_SOURCE_LINE}" ~/.bashrc; then
    echo "" >> ~/.bashrc
    echo "# R1 Mini workspace — $WS_NAME" >> ~/.bashrc
    echo "${WS_SOURCE_LINE}" >> ~/.bashrc
    echo "  Added to ~/.bashrc"
else
    echo "  Already present in ~/.bashrc, skipping."
fi




# Step 13: Install OLED display dependencies
echo ""
echo "=== [13/15] Installing OLED display dependencies ==="
sudo apt-get install -y python3-pip python3-pil libjpeg-dev zlib1g-dev \
    libfreetype6-dev liblcms2-dev libopenjp2-7 libtiff5
pip3 install Pillow luma.oled
echo "  OLED dependencies installed."

# Step 14: Copy display script and logo to home directory
echo ""
echo "=== [14/15] Copying display script and logo ==="
cp "$WS_DIR/src/r1_mini/.display.py" ~/.display.py
cp "$WS_DIR/src/r1_mini/.3.png" ~/.3.png
echo "  .display.py and .3.png copied to home directory."

# Step 15: Create and enable OLED systemd service
echo ""
echo "=== [15/15] Setting up OLED display systemd service ==="
USERNAME=$(whoami)
sudo bash -c "cat > /etc/systemd/system/r1mini_display.service << EOF
[Unit]
Description=R1MINI OLED Display Service
After=network.target i2c-1.device

[Service]
Type=simple
User=$USERNAME
WorkingDirectory=/home/$USERNAME/
ExecStart=/usr/bin/python3 /home/$USERNAME/.display.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF"
sudo systemctl daemon-reload
sudo systemctl enable r1mini_display.service
sudo systemctl start r1mini_display.service
echo "  OLED display service enabled and started."
echo "  Check status: sudo systemctl status r1mini_display.service"