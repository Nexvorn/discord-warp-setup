# Third-party software in the release package

The release zip (`DiscordWARP-Setup.zip`) bundles these unmodified official binaries. They are downloaded by `build.ps1`
from their official GitHub releases and verified against the SHA-256 digests GitHub publishes for each asset
(pinned in `src/setup/DiscordWarpLib.ps1`).

| Component | Version | License | Official source |
|---|---|---|---|
| mihomo (network engine) | v1.19.33 (`mihomo-windows-amd64-compatible-v1.19.33.zip`) | GPL-3.0 | https://github.com/MetaCubeX/mihomo (source code for this exact release: tag `v1.19.33`) |
| wgcf | 2.3.1 (`wgcf_2.3.1_windows_amd64.exe`) | MIT | https://github.com/ViRb3/wgcf (tag `v2.3.1`) |

mihomo is run unmodified as a separate program (`%ProgramFiles%\DiscordWARP\mihomo.exe`) with a generated configuration file.
The complete corresponding source code of the GPL-3.0 component is available at the link above (release tag).
This project's own scripts are licensed separately (see `LICENSE`). Cloudflare WARP is a service of Cloudflare, Inc.;
this project is not affiliated with Cloudflare, Discord, mihomo, Clash Verge Rev or wgcf.
Versions up to 1.2.0 of this package installed Clash Verge Rev 2.5.10 (GPL-3.0, https://github.com/clash-verge-rev/clash-verge-rev); 1.3.0 no longer does.
