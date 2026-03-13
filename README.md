# Android home server bootstrap

## Disclaimer

This is a vibe-coded project. It works when it works. There are no guarantees, no warranties, and probably a few weird edge cases.

If something breaks, gets stuck, or behaves like Android is haunted, just rerun the workflow. Seriously, rerunning the scripts a few times is part of the strategy here.

## What this project does

This project turns supported Android devices into small home-servers.

It automates the annoying host-side setup needed to:

- detect the device
- unlock the bootloader
- flash the target OS
- root the device with Magisk
- install Termux and Termux:Boot
- disable battery optimizations and makes Termux run all the time
- connects Wi‑Fi if configured
- prepare SSH access

The goal is simple: plug in an Android device and guide it into becoming a small server box. That you can manage over SSH (for example with Ansible).

## Supported devices

| Device              | Codename    | OS         |
| ------------------- | ----------- | ---------- |
| Google Pixel 7 Pro  | `cheetah`   | GrapheneOS |
| Google Pixel Tablet | `tangorpro` | GrapheneOS |

Notes:

- GrapheneOS is what this repo is currently set up for.
- LineageOS may actually be better for automation in theory, but it was not working here for some magical reason, so this project uses GrapheneOS for Pixel devices.

## How to use it

Create a [config/global.env](config/global.env) from the [config/global.env.example](config/global.env.example) template and fill up the password and Wi‑Fi details.

Run:

```sh
make interactive
```

Then follow the instructions.

The script pauses and tells you what to do on the device when manual confirmation is required.

If you get into trouble:

- run `make interactive` again
- rerun the scripts multiple times if needed
- do not assume the first weird failure is final

The workflow is meant to resume and continue when possible.

## What the script does

In short, the interactive workflow does this:

1. Checks that a supported Android device is connected.
2. Detects the device profile automatically when possible.
3. Downloads the required tools and OS images.
4. Verifies the downloaded files.
5. Helps you unlock the bootloader.
6. Flashes OS.
7. Boots the device back up and prepares it for the next steps.
8. Installs and sets up Magisk root.
9. Installs Termux and Termux:Boot.
10. Applies server-friendly tweaks (battery optimizations, always-on Termux).
11. Connects Wi‑Fi if configured.
12. Prepares SSH access so the device can be managed like a tiny server.

## Manual stuff you still need to do

Some steps still need human interaction on the device, including:

- enabling `OEM unlocking`
- confirming the bootloader unlock
- re-enabling `USB debugging` after flashing
- granting Magisk permissions
- opening Termux manually if Android decides to be difficult

## Config

Shared settings live in [config/global.env](config/global.env).

Device-specific settings live in (you probably don't need to change these):

- [config/cheetah.env](config/cheetah.env)
- [config/tangorpro.env](config/tangorpro.env)
