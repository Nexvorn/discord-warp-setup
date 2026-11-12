# discord-warp-setup

One-click Windows installer that sends **only Discord** through **Cloudflare WARP** (free), while every other
program keeps your normal internet connection. Built for networks where Discord is blocked (e.g. Turkey).

- Discord desktop app: chat, voice, video and screen share (TCP + UDP) through WARP.
- Discord in Chrome/Edge: discord.com traffic through WARP.
- Everything else (browser, games, Windows Update, ...) stays on your normal connection and DNS.
- Starts automatically with Windows; a small self-check repairs the tunnel at logon if needed.
- No account, no payment, no data cap. Each PC gets its own free WARP registration.

## Install (Windows 10/11, 64-bit)
1. Download `DiscordWARP-Setup.zip` from the [latest release](../../releases/latest) and extract it.
2. Turn off any other VPN.
3. Double-click `Install-DiscordWARP.cmd`, accept the Windows admin prompt, press OK. Takes 2-5 minutes.
4. Open Discord. If Discord is not installed yet, open discord.com in your browser and download it there.

Later: Start menu -> **Discord WARP** -> `Check` (health check) or `Update` (checks this page for a newer version and asks before installing).
Remove: `Uninstall-DiscordWARP.cmd`.

## How it works
- [Clash Verge Rev](https://github.com/clash-verge-rev/clash-verge-rev) (mihomo core) runs as a service in **selective TUN** mode:
  only Discord's IP ranges and Discord's DNS names (via Windows NRPT -> mihomo fake-IP) enter the tunnel; the default route is untouched.
- Rules send the Discord app (by process path) and Discord domains to a **WireGuard outbound to Cloudflare WARP**
  (registration created on the PC with [wgcf](https://github.com/ViRb3/wgcf)); no DIRECT fallback for Discord (fail-closed, no leak).
- WireGuard junk packets (`amnezia-wg-option`) defeat ISP detection of the plain WireGuard handshake.
- Discord's REST API (`discord.com`) is reached over Cloudflare **IPv6** inside WARP, avoiding the Cloudflare 429 rate limit
  ("Messages Failed To Load") that hits WARP's crowded shared IPv4 exit at peak times.
- `verify.ps1` (18 checks) and a logon self-heal task keep it healthy.

## Build from source
```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1     # -> dist\DiscordWARP-Setup.zip
```
Downloads the pinned official binaries (SHA-256 checked). Third-party licenses: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Notes
- Discord inside Android emulators is not covered.
- Running another full VPN at the same time can conflict; if Discord stops afterwards, quit and reopen Clash Verge.
- Not affiliated with Discord, Cloudflare, Clash Verge Rev, mihomo or wgcf. Check the laws and terms that apply to you.

---

## بالعربي

أداة تثبيت بضغطة واحدة لويندوز: تجعل **ديسكورد فقط** يمر عبر Cloudflare WARP المجاني، وباقي البرامج تبقى على إنترنتك العادي.

**التثبيت:**
1. نزّل الملف `DiscordWARP-Setup.zip` من [آخر إصدار](../../releases/latest) وفكّ ضغطه.
2. أطفئ أي برنامج VPN آخر.
3. اضغط مرتين على `Install-DiscordWARP.cmd`، ووافق على رسالة Windows، ثم اضغط OK. يأخذ من 2 إلى 5 دقائق.
4. افتح ديسكورد.

**لاحقاً:** من قائمة ابدأ ← **Discord WARP** ← `Check` للفحص، أو `Update` للتحديث (يسألك قبل التحديث).

**للإزالة:** شغّل `Uninstall-DiscordWARP.cmd`.
