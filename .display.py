import time
import socket
import sys
import signal
import subprocess
import os
from PIL import Image, ImageFont, ImageChops
from luma.core.interface.serial import i2c
from luma.core.render import canvas
from luma.oled.device import ssd1306

# --- Configuration ---
I2C_PORT = 1
I2C_ADDRESS = 0x3C
WIDTH = 128
HEIGHT = 32
BOOT_TIME_SEC = 5.0

# --- Global Device Variable ---
device = None
logo_img = None
font = None
text_x_base = 0

# --- Helper Functions ---

def get_text_width(draw, text, font):
    try:
        return font.getlength(text)
    except AttributeError:
        try:
            return draw.textsize(text, font=font)[0]
        except AttributeError:
            return len(text) * 6

def get_ip_address():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(0.1)
    try:
        s.connect(('8.8.8.8', 1))
        IP = s.getsockname()[0]
    except Exception:
        IP = '127.0.0.1'
    finally:
        s.close()
    return IP

def get_ssid():
    """Fetches the current Wi-Fi SSID."""
    try:
        ssid = subprocess.check_output(['iwgetid', '-r'], text=True).strip()
        if ssid:
            return ssid
    except Exception:
        pass
    return "No Wi-Fi"

def trim_borders(im):
    bg = Image.new(im.mode, im.size, (0, 0, 0))
    diff = ImageChops.difference(im, bg)
    diff = ImageChops.add(diff, diff, 2.0, -100)
    bbox = diff.getbbox()
    if bbox:
        return im.crop(bbox)
    return im

def process_logo(image_path):
    try:
        img = Image.open(image_path).convert("RGB")
        img = trim_borders(img)
        aspect_ratio = img.width / img.height
        new_height = 32
        new_width = int(new_height * aspect_ratio)
        img = img.resize((new_width, new_height), Image.Resampling.LANCZOS)
        img = img.convert("L")
        img = img.point(lambda p: 255 if p > 60 else 0)
        img = img.convert("1")
        return img
    except Exception as e:
        print(f"Logo Error: {e}")
        return None

# --- Shutdown/Reboot Handler ---
def check_system_state():
    try:
        output = subprocess.check_output(['systemctl', 'list-jobs'], text=True)
        if 'reboot.target' in output:
            return 'REBOOT'
        elif 'poweroff.target' in output or 'shutdown.target' in output:
            return 'SHUTDOWN'
    except Exception:
        pass
    return 'STOPPING'

def handle_exit(signum, frame):
    global device, logo_img, font, text_x_base

    if device:
        state = check_system_state()
        message = "Stopping..."

        if state == 'REBOOT':
            message = "Restarting..."
        elif state == 'SHUTDOWN':
            message = "Shutting Down..."

        try:
            with canvas(device) as draw:
                if logo_img:
                    draw.bitmap((0, 0), logo_img, fill="white")
                draw.text((text_x_base, 0), "GEFIER R1", fill="white", font=font)
                draw.line((text_x_base, 11, WIDTH, 11), fill="white")
                draw.text((text_x_base, 14), message, fill="white", font=font)
        except Exception:
            pass
        time.sleep(3)
    sys.exit(0)

# --- Main Logic ---
def main():
    global device, logo_img, font, text_x_base

    print(f"Initializing Display on Bus {I2C_PORT}...")
    try:
        serial = i2c(port=I2C_PORT, address=I2C_ADDRESS)
        device = ssd1306(serial, width=WIDTH, height=HEIGHT)
    except Exception as e:
        print(f"I2C Initialization Error: {e}")
        return

    logo_img = process_logo(".automind.png")
    font = ImageFont.load_default()

    logo_w = logo_img.width if logo_img else 0
    text_x_base = logo_w + 2

    scroll_text = "Developed by Automind Dynamics"
    scroll_x = WIDTH

    with canvas(device) as draw:
        text_len = get_text_width(draw, scroll_text, font)

    # ==========================================
    # PHASE 1: LOADING SCREEN (5s)
    # ==========================================
    start_time = time.time()

    while True:
        elapsed = time.time() - start_time
        if elapsed >= BOOT_TIME_SEC:
            break

        boot_progress = min(elapsed / BOOT_TIME_SEC, 1.0)

        # Scroll Math
        scroll_x -= 4
        if scroll_x < -text_len:
            scroll_x = WIDTH

        with canvas(device) as draw:
            # 1. Draw Scrolling Text (Bottom Layer)
            draw.text((scroll_x, 22), scroll_text, fill="white", font=font)

            # 2. Draw MASK (Black Box) over the Logo Area
            draw.rectangle((0, 0, text_x_base, 32), fill="black")

            # 3. Draw Logo & Static Content (Top Layer)
            if logo_img:
                draw.bitmap((0, 0), logo_img, fill="white")

            draw.text((text_x_base, 0), "GEFIER R1", fill="white", font=font)

            # Loading Bar
            bar_x = text_x_base
            bar_y = 14
            bar_w = WIDTH - text_x_base - 2
            bar_h = 5
            draw.rectangle((bar_x, bar_y, bar_x + bar_w, bar_y + bar_h),
                           outline="white", fill="black")

            fill_w = int(bar_w * boot_progress)
            if fill_w > 2:
                draw.rectangle((bar_x+1, bar_y+1, bar_x + fill_w - 1,
                                bar_y + bar_h - 1), fill="white")

        time.sleep(0.02)

    # ==========================================
    # PHASE 2: STATUS SCREEN
    # ==========================================
    print("Switching to Status Mode...")

    last_network_check = 0
    ip = ""
    ssid = ""
    ssid_scroll_x = text_x_base

    while True:
        try:
            current_time = time.time()

            # Fetch network info every 5 seconds so we don't lag the animation
            if current_time - last_network_check >= 5.0:
                ip = get_ip_address()
                ssid = get_ssid()
                last_network_check = current_time

            with canvas(device) as draw:
                # Calculate text width to determine if scrolling is needed
                ssid_w = get_text_width(draw, ssid, font)
                max_visible_w = WIDTH - text_x_base

                # --- Update Scroll Position ---
                if ssid_w > max_visible_w:
                    ssid_scroll_x -= 2 # Speed of the scroll
                    # Reset position once it scrolls completely out of view
                    if ssid_scroll_x < (text_x_base - ssid_w - 10): 
                        ssid_scroll_x = WIDTH
                else:
                    ssid_scroll_x = text_x_base # Keep static if it fits

                # 1. Draw scrolling SSID (Bottom Layer)
                draw.text((ssid_scroll_x, 12), ssid, fill="white", font=font)

                # 2. Draw MASK (Black Box) over the Logo Area to hide text sliding behind it
                draw.rectangle((0, 0, text_x_base, 32), fill="black")

                # 3. Draw Logo
                if logo_img:
                    draw.bitmap((0, 0), logo_img, fill="white")

                # 4. Draw Static Text (Top Layer)
                draw.text((text_x_base, -1), "GEFIER R1", fill="white", font=font)
                draw.line((text_x_base, 10, WIDTH, 10), fill="white")
                draw.text((text_x_base, 22), f"{ip}", fill="white", font=font)

            # Short sleep for smooth animation frame rate (~25 FPS)
            time.sleep(0.04) 

        except Exception as e:
            print(f"Error: {e}")
            time.sleep(1)

if __name__ == "__main__":
    signal.signal(signal.SIGTERM, handle_exit)
    signal.signal(signal.SIGINT, handle_exit)
    try:
        main()
    except KeyboardInterrupt:
        pass
