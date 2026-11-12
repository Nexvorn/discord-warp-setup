# Third-party software in the release package

The release zip (`DiscordWARP-Setup.zip`) bundles these unmodified official binaries. They are downloaded by `build.ps1`
from their official GitHub releases and verified against the SHA-256 digests GitHub publishes for each asset
(pinned in `src/setup/DiscordWarpLib.ps1`).

| Component | Version | License | Official source |
|---|---|---|---|
| Clash Verge Rev (includes the mihomo core) | 2.5.10 (`Clash.Verge_2.5.10_x64-setup.exe`) | GPL-3.0 | https://github.com/clash-verge-rev/clash-verge-rev (source code for this exact release: tag `v2.5.10`) |
| mihomo (inside Clash Verge Rev) | v1.19.33 | GPL-3.0 | https://github.com/MetaCubeX/mihomo |
| wgcf | 2.3.1 (`wgcf_2.3.1_windows_amd64.exe`) | MIT | https://github.com/ViRb3/wgcf (tag `v2.3.1`) |

The complete corresponding source code of the GPL-3.0 components is available at the links above (release tags).
This project's own scripts are licensed separately (see `LICENSE`). Cloudflare WARP is a service of Cloudflare, Inc.;
this project is not affiliated with Cloudflare, Discord, Clash Verge Rev, mihomo or wgcf.
