#!/bin/bash
set -e
set -o pipefail

WS_DIR=~/r1_ws

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
rosdep update
rosdep install --from-paths src --ignore-src -y

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
sudo cp "$(dirname "${BASH_SOURCE[0]}")/99-r1mini.rules" /etc/udev/rules.d/99-r1mini.rules
sudo udevadm control --reload-rules
sudo udevadm trigger
echo "  udev rules installed and applied."