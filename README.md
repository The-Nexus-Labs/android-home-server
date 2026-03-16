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

To reflash GrapheneOS and rerun every post-flash step without skipping, use `make interactive INTERACTIVE_ARGS=--force`.

For an individual step, run `make step STEP=<step-key> ACTION=run`.
Examples:

- `make step STEP=prepare-assets ACTION=apply`
- `make step STEP=connect-wifi ACTION=guide`

If something fails, run `make interactive` again. The workflow is designed to resume when possible, and rerunning it multiple times is expected.

## 👆 Manual steps still required

- enable `OEM unlocking`
- confirm bootloader unlock
- re-enable `USB debugging` after flashing
- grant Magisk permissions
- grant Magisk Superuser access to Termux before the SSH setup step

## Docs

Additional docs: [docs/index.md](docs/index.md)
