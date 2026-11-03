# Acer Sense — Dux Shell Plugin (Fork)

A comprehensive laptop control center for **Acer Nitro / Predator** laptops in your [Dux Shell](https://duxlabs.dev) (formerly DankMaterialShell / DMS) bar. A customizable bar pill displays your current power profile and live metrics; clicking it opens a feature-packed popout control center.

> **Fork Notice:** This repository is an expanded fork of [raphamzn/dms-acer-sense](https://github.com/raphamzn/dms-acer-sense) maintained by **[Dhruv1249](https://github.com/Dhruv1249/dms-acer-sense)**. It brings complete feature parity with the [Linuwu-Sense](https://github.com/0x7375646F/Linuwu-Sense) kernel module, including interactive 4-zone RGB keyboard control, custom fan speeds, battery calibration, LCD overdrive, boot animation sound toggles, in-extension helper setup, and AMD Ryzen CPU temperature support.

---

## ✨ Features

- **Power Profiles** — Switch between Low-Power / Quiet / Balanced / Performance / Turbo (`platform_profile` synchronized with `power-profiles-daemon`).
- **Fan Control** — Auto, Max, and **Custom Fan Speeds** (interactive sliders and numeric inputs with step size 5, CPU & GPU link option, and quick presets).
- **Keyboard RGB Lighting (`four_zoned_kb`)**:
  - **Dynamic Effects**: 8 lighting modes (Static, Breathing, Neon, Wave, Shifting, Zoom, Meteor, Twinkling) with Speed (0–9), Brightness (0–100%), Direction (L→R / R→L), and color picker presets.
  - **Per-Zone Colors**: 4-zone interactive keyboard visualizer with individual zone color pickers, brightness control, and quick presets (Predator Cyan, Rainbow, Cyberpunk).
  - Compatibility notice for 2025+ models using ENEK5130 i2c-HID controllers.
- **Battery Management**:
  - Live charge level, charging status, and cycle count.
  - **80% Charge Limiter** toggle to preserve battery lifespan.
  - **Battery Calibration** cycle (100% → 0% → 100%) with safety confirmation.
  - **USB Power-off Charging** cutoff selector (Off, 10%, 20%, 30%).
- **Display & Audio Toggles**:
  - **LCD Overdrive** — minimize panel latency and ghosting.
  - **Boot Animation Sound** — enable or disable startup chime.
  - **Backlight Timeout** — turn off RGB backlight after 30 seconds of idle.
- **Hardware Turbo Mode** — live status badge when the hardware Turbo key is engaged (`turbo_sense`).
- **Telemetry & GPU**:
  - Real-time CPU & GPU temperatures and fan RPMs.
  - Intel Core (`coretemp`) and AMD Ryzen (`k10temp` / `zenpower`) CPU temperature support.
  - Power source indicator (AC Connected vs. Battery).
  - Discrete GPU mode switcher via `envycontrol` (hybrid, integrated, nvidia) with safety confirmation.
  - Zero idle dGPU power drain: discrete GPU metrics are only queried while the popout is open.
- **In-Extension Setup & Guidance**:
  - Automatic detection of privileged helper status (`/usr/local/bin/acer-ctl`).
  - **"Authenticate with Password"** button — one-click graphical setup using Polkit (`pkexec`).
  - **"Copy Terminal Command"** button with clipboard integration.

---

## Requirements

1. **Dux Shell** (or DankMaterialShell) ≥ 1.4.0
2. An **Acer Nitro or Predator** gaming laptop with the **[linuwu-sense](https://github.com/0x7375646F/Linuwu-Sense)** DKMS kernel module installed and loaded.
3. *Optional:* `nvidia-smi` and `envycontrol` for discrete GPU monitoring and switching.

---

## Installing `linuwu-sense` Kernel Module

The fan, RGB, battery, and display controls interface with sysfs nodes provided by the [**linuwu-sense**](https://github.com/0x7375646F/Linuwu-Sense) DKMS kernel module.

**Arch Linux / CachyOS** (AUR):
```bash
yay -S linuwu-sense-dkms-git      # or: paru -S linuwu-sense-dkms-git
sudo modprobe linuwu_sense        # load module (auto-loads on boot)
```

**Debian / Ubuntu**:
```bash
sudo apt install linux-headers-$(uname -r) dkms
git clone https://github.com/0x7375646F/Linuwu-Sense.git
cd Linuwu-Sense
sudo make install
```

**Fedora / openSUSE / Other Distros**:
```bash
# Fedora:
sudo dnf install kernel-devel-$(uname -r) dkms
# openSUSE:
sudo zypper in kernel-default-devel dkms

git clone https://github.com/0x7375646F/Linuwu-Sense.git
cd Linuwu-Sense
sudo make install
```

Verify the module is loaded:
```bash
ls /sys/devices/platform/acer-wmi/nitro_sense   # or predator_sense
```

---

## Installation & Setup

### 1. Install Plugin

Clone into your Dux Shell plugins directory:

```bash
# For modern Dux Shell:
git clone https://github.com/Dhruv1249/dms-acer-sense.git \
  ~/.config/dms/plugins/acerSense

# If your installation uses legacy DankMaterialShell paths:
# git clone https://github.com/Dhruv1249/dms-acer-sense.git ~/.config/DankMaterialShell/plugins/acerSense

dms restart
```

### 2. Privileged Helper Setup (Required for Controls)

Writing to `platform_profile`, fan speeds, battery limiter, and RGB sysfs files requires elevated privileges. Acer Sense includes an auditable helper script (`helper/acer-ctl`) and a single `NOPASSWD` sudoers entry scoped strictly to that binary.

You can set this up in **two easy ways**:

#### Option A: Inside the Extension (Recommended)
1. Open the Acer Sense popout or settings in Dux Shell.
2. Click the **"Authenticate with Password"** button in the warning banner.
3. Enter your password in the native Polkit prompt — setup completes automatically!

#### Option B: Terminal Command
Run the installation script once:
```bash
sudo sh ~/.config/dms/plugins/acerSense/helper/install.sh
```

*(You can also click the "Copy Terminal Command" button in the popout to copy this exact command to your clipboard).*

### 3. Enable in Dux Shell

1. Open Dux Shell Settings: `Mod + ,`
2. Go to **Plugins** → **Scan for Plugins** → Enable **Acer Sense**.
3. Add `acerSense` to your bar layout (**Appearance** → **DankBar Layout**).

---

## Settings

- **Pill Content** — Configure what is shown next to the bar icon: CPU temp, Fan RPM, or icon only.
- **Fan Quiet Speed (%)** — The fan percentage used by the "Quiet" preset (default: 40%).
- **Telemetry Refresh Interval** — Sysfs polling frequency (2s, 4s, 6s, or 10s).
- **Helper Status Card** — Visual indicator of helper installation, with one-click install and copy buttons.

---

## Security

`acer-ctl` is a lightweight POSIX shell script that validates every parameter against strict whitelists before touching any sysfs node. The sudoers rule grants `NOPASSWD` to `/usr/local/bin/acer-ctl` only for your user account. Review `helper/acer-ctl` and `helper/install.sh` at any time.

---

## Credits & Acknowledgments

- **Original Author**: [raphamzn](https://github.com/raphamzn/dms-acer-sense) for creating the initial Acer Sense DMS plugin.
- **Kernel Module**: [0x7375646F](https://github.com/0x7375646F/Linuwu-Sense) and contributors for reverse-engineering PredatorSense and creating the `linuwu-sense` Linux driver.
- **Desktop Environment**: [Dux Labs](https://duxlabs.dev) / [AvengeMedia](https://github.com/AvengeMedia/DankMaterialShell) for Dux Shell and Quickshell.
- **Fork Maintainer**: [Dhruv1249](https://github.com/Dhruv1249) for extended feature parity and maintenance.

---

## License

MIT — see [LICENSE](LICENSE).
