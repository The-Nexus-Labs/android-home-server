## 📶 Wi-Fi MAC policy

For GrapheneOS home-server use, provisioning saves the configured Wi-Fi network with MAC randomization disabled so the device keeps a stable hardware MAC on that network.

Official GrapheneOS documentation:

- [Wi-Fi privacy: Associated with an Access Point (AP)](https://grapheneos.org/usage#wifi-privacy-associated)

That section documents that GrapheneOS defaults to `Use per-connection randomized MAC` and that the manual control is available at:

- `Settings > Network & internet > Internet > NETWORK > Privacy`

For a home server, the equivalent manual choice is `Use device MAC`.
