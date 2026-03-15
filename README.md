oc<h1 align="center">📱➡️🖥️ Android Home Server Bootstrap</h1>

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

For an individual step, run `make step STEP=<step-key> ACTION=run`.
Examples:

- `make step STEP=prepare-assets ACTION=apply`
- `make step STEP=connect-wifi ACTION=guide`

If something fails, run `make interactive` again. The workflow is designed to resume when possible, and rerunning it multiple times is expected.

## 🧱 Layout

- Shared shell code lives in [src](src).
- Each provisioning step lives in its own folder under [src/steps](src/steps).
- Every step module exposes the same shell interface: `step_name`, `step_is_done`, `step_apply`, and `step_guide`.
- Step-owned payloads now live beside the step that installs or uses them.

## 🛠️ Workflow summary

1. Check the connected device.
2. Download, verify, and extract pinned tools and OS images.
3. Guide bootloader unlock.
4. Flash the OS.
5. Install Magisk root.
6. Connect Wi‑Fi if configured.
7. Disable GrapheneOS per-connection MAC randomization for that network.
8. Enable GrapheneOS Send device name for that network.
9. Disable the OS update client.
10. Install the Magisk battery-tuning service.
11. Install Termux and Termux:Boot.
12. Stage the Termux bootstrap and SSH configuration.
13. Disable the Magisk UI Superuser notification.
14. Disable the Magisk shell grant notification.
15. Disable the Magisk Termux grant notification.
16. Verify SSH and rerun every earlier step check.

## 👆 Manual steps still required

- enable `OEM unlocking`
- confirm bootloader unlock
- re-enable `USB debugging` after flashing
- grant Magisk permissions
- open Termux manually if Android blocks automation

## Docs

Additional docs: [docs/index.md](docs/index.md)
