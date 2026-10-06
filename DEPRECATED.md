# Retired repository â€” archived 2026-10-06

**This repository is archived and no longer maintained.** It is kept read-only so its history and any inbound links stay resolvable. Nothing here should be built on.

## Superseded by

**[neohiro/linux](https://github.com/neohiro/linux)** â€” one cross-distro guide covering Debian/Ubuntu/RHEL/Fedora/SUSE/Arch/Manjaro.

## Why it was retired

Superseded by **scope, not correction**. The hardening advice here is not wrong and most of it still applies; it was simply Ubuntu-only. `neohiro/linux` covers the same ground for nine distributions and detects the right one at runtime.

Keeping a second, narrower guide meant two files to update whenever a recommendation changed â€” and readers landing on the wrong one for their distribution. The README already carried this redirect and the install URL moved with it:

```bash
curl -fsSL https://raw.githubusercontent.com/neohiro/linux/main/linuxinstall.sh | sudo bash -s --
```

## Where each concern went

| Concern | Now |
|---|---|
| Ubuntu post-install hardening | [neohiro/linux](https://github.com/neohiro/linux) |
| Encrypted DNS, Tor routing | [neohiro/dnscrypt-proxy-gui](https://github.com/neohiro/dnscrypt-proxy-gui), [neohiro/Cripple-NetStrip](https://github.com/neohiro/Cripple-NetStrip) |
| Snap / flatpak control, GNOME privacy | [neohiro/Cripple-NetStrip](https://github.com/neohiro/Cripple-NetStrip) |
| ShadowSocks client | [neohiro/ShadowSocks](https://github.com/neohiro/ShadowSocks) |