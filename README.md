


# 🐧 Void Linux KDE Setup (AMD Optimized)

A fully automated post-install script that turns a fresh Void Linux base install (glibc, x86_64) into a working KDE Plasma desktop with PipeWire, heavily tuned for AMD hardware (Ryzen CPU + Radeon GPU).

It follows official Void Linux documentation, handles `runit` services correctly, reports every failed package at the end, and keeps a full execution log.

> **⚠️ Warning:** This script runs as `root`, enables runit services, switches networking from `dhcpcd` to `NetworkManager`, and reboots the machine. Please review the code before running it.

## 🤖 AI Assistance

This script was written with the assistance of Claude (Anthropic) and then tested by the author on a virtual machine and on real hardware. As with any script that runs as root, please review the code before using it on your own system.

## ✨ Features

* **Core System:** Full system update & `void-repo-nonfree` integration.
* **AMD Optimized:** `linux-firmware-amd` and an initramfs rebuild (`dracut`) for early KMS loading.
* **Graphics Stack:** Mesa, Vulkan (RADV), VA-API, `xf86-video-amdgpu`, and minimal Xorg.
* **Desktop Environment:** KDE Plasma, SDDM, Dolphin, Konsole, and core KDE utilities.
* **Audio:** PipeWire + WirePlumber + PulseAudio compatibility (configured via official Void handbook guidelines).
* **System Services:** Correctly sets up `dbus`, `elogind`, `polkitd`, `sddm`, and `NetworkManager` via `runit`.
* **Monitoring Tools:** Includes `lm_sensors`, `ksystemstats`, `radeontop`, and `fastfetch`.
* **Safety Built-in:** Automatic VM detection, user group assignments (audio, video, network), and graceful failure handling (does not stop the whole run if one package fails).

## 📋 Requirements

* Fresh Void Linux base install (glibc, x86_64)
* Working internet connection
* A regular user account (UID 1000)
* ~12 GB of free disk space
* **AMD Hardware** (Script is explicitly written for Ryzen + Radeon setups. It does *not* include Intel microcode, NVIDIA drivers, or laptop-specific tools like `tlp`).

## 🚀 Installation & Usage

Log in as `root` (`su -`) and run the script directly:

```bash
xbps-install -Sy curl
curl -O [https://raw.githubusercontent.com/Mrucxek21/void-linux-kde-install-script/main/void-kde-install.sh](https://raw.githubusercontent.com/Mrucxek21/void-linux-kde-install-script/main/void-kde-install.sh)
bash void-kde-install.sh

```

**Alternatively, clone the repository:**

```bash
xbps-install -Sy git
git clone [https://github.com/Mrucxek21/void-linux-kde-install-script.git](https://github.com/Mrucxek21/void-linux-kde-install-script.git)
cd void-linux-kde-install-script
su -
bash void-kde-install.sh

```

## ⚙️ Options

| Flag | Description |
| --- | --- |
| `-y`, `--yes` | **No prompts:** automatically enable SDDM, switch network, and reboot. |
| `--no-nm` | **Keep `dhcpcd`:** Skips switching to NetworkManager (useful for SSH installs). |
| `-h`, `--help` | Show usage information. |

*Without `-y`, the script asks at the end whether to enable SDDM and reboot. If you decline, it provides manual commands to finish the setup.*

## 🛠️ What it does (Step-by-Step)

| Step | Action |
| --- | --- |
| **1** | System update & `void-repo-nonfree` setup |
| **2** | AMD firmware installation |
| **3** | GPU stack (Mesa, Vulkan, VA-API, Xorg) |
| **4** | System services packages (`dbus`, `elogind`, `polkit`) |
| **5** | KDE Plasma, SDDM, and base applications |
| **6** | Monitoring tools & `sensors-detect` |
| **7** | PipeWire configuration |
| **8** | `runit` services & user groups |
| **9** | Package cache cleanup |

## 🧪 Tested On

* **Virtual Machine:** VirtualBox (Void Linux base install, Plasma X11 session)
* **Real Hardware (Author's Rig):**
* CPU: AMD Ryzen 9 5950X
* GPU: AMD Radeon RX 6800 XT
* Motherboard: Gigabyte X570 Gaming X
* RAM: 64 GB



## ⚠️ Known Issues & Tips

* **Gigabyte Motherboards (`it87`):** The Super I/O chip may need the kernel parameter `acpi_enforce_resources=lax`, otherwise `modprobe it87` fails with "resource busy". The script will warn you instead of failing.
* **VirtualBox:** Plasma on Wayland can crash VirtualBox with 3D acceleration enabled. In a VM, disable 3D acceleration and pick the **Plasma (X11)** session in SDDM.
* **Package Names:** Void occasionally renames packages (e.g., `kde5` vs `kde-plasma`). The script tries alternatives and lists anything missing in the final summary.

## 🚑 Troubleshooting

If something goes wrong, check the end-of-run summary and the log file:

```bash
less /var/log/void-kde-setup.log

```

If SDDM does not start after reboot, check your services:

```bash
sv status sddm dbus elogind polkitd
ls /var/service

```

*When opening an issue, please attach the relevant part of the log file and the output of the commands above.*

## 📄 License

Released under the [MIT License](https://www.google.com/search?q=LICENSE).



