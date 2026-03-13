## 🔄 OTA update policy

This repo disables the OS update client during provisioning so updates only happen when explicitly managed.

- `make updates-disable` disables the current OS update client.
- `make updates-enable` re-enables it.
- `make updates-status` shows the current mode.

On GrapheneOS, this currently disables the `System Updater` app, matching the official guidance for turning off automatic background updates when you want to manage updates yourself.
