<h1 align="center">📱➡️🖥️ Android Home Server Bootstrap</h1>

<p align="center">
Turn supported Android devices into small home servers with SSH access.
</p>

<p align="center">
	<b>GrapheneOS</b> · <b>Magisk</b> · <b>Termux</b> · <b>Termux:Boot</b>
</p>

> [!WARNING]
> **Vibe-coded project. No guarantees.**

## ✨ What it does

Automates the host-side work to turn the screen-broken Android device into a home server that you can mange over SSH.

However somewhat working screen is still required for the initial setup, as you need to do some manual confirmations and setup.

## 📦 Supported devices

| Device              | Codename    | OS         |
| ------------------- | ----------- | ---------- |
| Google Pixel 7 Pro  | `cheetah`   | GrapheneOS |
| Google Pixel Tablet | `tangorpro` | GrapheneOS |

> [!NOTE]
> LineageOS may be better for automation in theory, but it was not working here for some magical reason. This repo currently targets GrapheneOS on Pixel devices.

## 🚀 Usage

1. Create [config/global.env](config/global.env) from [config/global.env.example](config/global.env.example).
2. Fill in the password and Wi‑Fi settings.
3. Run `make interactive`.
4. Follow the on-device prompts.

If something fails, run `make interactive` again. The workflow is designed to resume when possible, and rerunning it multiple times is expected.

## 🛠️ Workflow summary

1. Check the connected device.
2. Detect the device profile.
3. Download tools and OS images.
4. Verify downloads.
5. Guide bootloader unlock.
6. Flash the OS.
7. Boot and prepare the device.
8. Install Magisk root.
9. Install Termux and Termux:Boot.
10. Disable battery optimizations and keep Termux running.
11. Connect Wi‑Fi if configured.
12. Disable the OS update client.
13. Set up SSH.

## 🔄 OTA update policy

This repo disables the OS update client during provisioning so updates only happen when explicitly managed.

- `make updates-disable` disables the current OS update client.
- `make updates-enable` re-enables it.
- `make updates-status` shows the current mode.

On GrapheneOS, this currently disables the `System Updater` app, matching the official guidance for turning off automatic background updates when you want to manage updates yourself.

## 👆 Manual steps still required

- enable `OEM unlocking`
- confirm bootloader unlock
- re-enable `USB debugging` after flashing
- grant Magisk permissions
- open Termux manually if Android blocks automation
