# discord-warp-setup

One-click Windows installer that sends **only Discord** through **Cloudflare WARP** (free), while every other
program keeps your normal internet connection. Built for networks where Discord is blocked (e.g. Turkey).

- Discord desktop app: chat, voice, video and screen share (TCP + UDP) through WARP.
- Discord in Chrome/Edge/Brave/Firefox: discord.com traffic through WARP.
- Everything else (browser, games, Windows Update, ...) stays on your normal connection and DNS.
- Starts automatically with Windows as a small background service that repairs the tunnel by itself.
- A small Arabic app (Start menu + tray icon): check, repair, pause, update, problem report, uninstall.
- No account, no payment, no data cap. Each PC gets its own free WARP registration.

## Install (Windows 10/11, 64-bit)
1. Download `DiscordWARP-Setup.zip` from the [latest release](../../releases/latest) and extract it.
2. Turn off any other VPN.
3. Double-click `Install-DiscordWARP.cmd`, press **Install** (تثبيت), accept the Windows admin prompt. Takes 1-3 minutes.
4. Open Discord (the app has a button that opens it, or downloads the official installer if Discord is missing).

Upgrading from 1.0-1.2: install 1.3 over it. Clash Verge is stopped, the same WARP registration is reused, and you choose whether Clash Verge is removed.

## How it works
- The official [mihomo](https://github.com/MetaCubeX/mihomo) engine runs unmodified, supervised by a SYSTEM scheduled task
  (`DiscordWARP-Engine`, `Engine.ps1`), in **selective TUN** mode: only Discord's IP ranges and Discord's DNS names
  (via Windows NRPT -> mihomo fake-IP) enter the tunnel; the default route is untouched.
- Rules send the Discord app (by process path) and Discord domains to a **WireGuard outbound to Cloudflare WARP**
  (registration created on the PC with [wgcf](https://github.com/ViRb3/wgcf)); no DIRECT fallback for Discord (fail-closed, no leak).
- WireGuard junk packets (`amnezia-wg-option`) defeat ISP detection of the plain WireGuard handshake.
- Discord's REST API (`discord.com`) is reached over Cloudflare **IPv6** inside WARP, avoiding the Cloudflare 429 rate limit
  ("Messages Failed To Load") that hits WARP's crowded shared IPv4 exit at peak times.
- The supervisor tests the Discord API through WARP every 2 minutes and recreates the tunnel after 3 failed rounds
  (at most 3 times per hour, never during a Discord call). The engine API is only on a local named pipe with a random secret.
- Files: `%ProgramFiles%\DiscordWARP` (engine + scripts), `%ProgramData%\DiscordWARP` (config, WARP account with a private ACL, logs).

## Build from source
```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1     # -> dist\DiscordWARP-Setup.zip
```
Downloads the pinned official binaries (SHA-256 checked). Third-party licenses: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Notes
- Discord inside Android emulators is not covered.
- To use another full VPN, press **Pause** in the app first and **Resume** afterwards.
- Not affiliated with Discord, Cloudflare, mihomo or wgcf. Check the laws and terms that apply to you.

---

## بالعربي

أداة تثبيت بضغطة واحدة لويندوز: تجعل **ديسكورد فقط** يمر عبر Cloudflare WARP المجاني، وباقي البرامج تبقى على إنترنتك العادي.

**التثبيت:**
1. نزّل الملف `DiscordWARP-Setup.zip` من [آخر إصدار](../../releases/latest) وفكّ ضغطه.
2. أطفئ أي برنامج VPN آخر.
3. اضغط مرتين على `Install-DiscordWARP.cmd`، ثم زر **تثبيت**، ووافق على رسالة Windows. يأخذ من دقيقة إلى 3 دقائق.
4. افتح ديسكورد.

**لاحقاً:** تطبيق **Discord WARP** في قائمة ابدأ وبجانب الساعة: فحص، إصلاح، إيقاف مؤقت، البحث عن تحديث، تقرير مشكلة، إزالة.

**من نسخة قديمة (1.0 إلى 1.2):** ثبّت فوقها مباشرة؛ لم يعد Clash Verge مطلوباً.

**للإزالة:** زر "إزالة" في التطبيق، أو إعدادات Windows ← التطبيقات، أو `Uninstall-DiscordWARP.cmd`.
