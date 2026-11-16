# discord-warp-setup

One-click Windows installer that sends **only Discord** through **Cloudflare WARP** (free), while every other
program keeps your normal internet connection. Built for networks where Discord is blocked (e.g. Turkey).

- Discord desktop app: chat, voice, video and screen share (TCP + UDP) through WARP.
- Discord in Chrome/Edge/Brave/Firefox: discord.com traffic through WARP.
- Everything else (browser, games, Windows Update, ...) stays on your normal connection and DNS.
- Starts automatically with Windows as a small background service that repairs the tunnel by itself.
- Works next to other VPNs: while another VPN is connected, Discord WARP pauses itself and resumes when it disconnects.
- A small Arabic app (Start menu + tray icon): check, repair, pause, update, problem report, uninstall.
- No account, no payment, no data cap. Each PC gets its own free WARP registration.

## Install (Windows 10/11, 64-bit)
1. Download `DiscordWARP-Setup.zip` from the [latest release](../../releases/latest) and extract it.
2. Disconnect any other VPN while installing (afterwards it does not matter, see below).
3. Double-click `Install-DiscordWARP.cmd`, press **Install** (تثبيت), accept the Windows admin prompt. Takes 1-3 minutes.
4. Open Discord (the app has a button that opens it, or downloads the official installer if Discord is missing).

Upgrading: press **Check for updates** in the app, or install the new version over the old one. From 1.0-1.2: Clash Verge is stopped, the same WARP registration is reused, and you choose whether Clash Verge is removed.

## How it works
- The official [mihomo](https://github.com/MetaCubeX/mihomo) engine runs unmodified, supervised by a SYSTEM scheduled task
  (`DiscordWARP-Engine`, `Engine.ps1`), in **selective TUN** mode: only Discord's IP ranges and Discord's DNS names
  (via Windows NRPT -> mihomo fake-IP) enter the tunnel; the default route is untouched.
- Rules send the Discord app (by process path) and Discord domains to a **WireGuard outbound to Cloudflare WARP**
  (registration created on the PC with [wgcf](https://github.com/ViRb3/wgcf)); no DIRECT fallback for Discord (fail-closed, no leak).
- WireGuard junk packets (`amnezia-wg-option`) defeat ISP detection of the plain WireGuard handshake.
- Discord's REST API (`discord.com`) is reached over Cloudflare **IPv6** inside WARP, avoiding the Cloudflare 429 rate limit
  ("Messages Failed To Load") that hits WARP's crowded shared IPv4 exit at peak times.
- The supervisor tests the Discord API through WARP every minute, including the time to open a new connection, and recreates
  the tunnel after 3 failed rounds (further attempts of the same failure wait 2, 5, 10, then 15 minutes; never during a Discord call).
  Each recreation uses the next WARP port (2408 -> 4500 -> 1701 -> 500) because an ISP may throttle one port; the port that
  works is remembered. It also recreates the tunnel when the network changes. The engine API is only on a local named pipe with a random secret.
- **Other VPNs** (1.4): every 3 s the supervisor checks which adapter Windows uses for internet traffic. While another full
  VPN is connected (NordVPN, Windscribe, Proton VPN, ExpressVPN, Mullvad, WireGuard, OpenVPN, the Cloudflare WARP app,
  a Windows VPN connection, ...), the engine is stopped and Discord simply uses that VPN; when it disconnects, Discord WARP
  resumes with a fresh tunnel. WARP traffic sent while another VPN connected or disconnected could leave the tunnel slow for
  a long time, so it is not sent at all.
- Files: `%ProgramFiles%\DiscordWARP` (engine + scripts), `%ProgramData%\DiscordWARP` (config, WARP account with a private ACL, logs).

## Build from source
```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1     # -> dist\DiscordWARP-Setup.zip
```
Downloads the pinned official binaries (SHA-256 checked). Third-party licenses: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Notes
- Discord inside Android emulators is not covered.
- Another VPN that blocks all other traffic while disconnected ("kill switch" left on) cannot be detected; turn that option off.
- Not affiliated with Discord, Cloudflare, mihomo or wgcf. Check the laws and terms that apply to you.

---

## بالعربي

أداة تثبيت بضغطة واحدة لويندوز: تجعل **ديسكورد فقط** يمر عبر Cloudflare WARP المجاني، وباقي البرامج تبقى على إنترنتك العادي.

**التثبيت:**
1. نزّل الملف `DiscordWARP-Setup.zip` من [آخر إصدار](../../releases/latest) وفكّ ضغطه.
2. افصل أي برنامج VPN آخر أثناء التثبيت فقط.
3. اضغط مرتين على `Install-DiscordWARP.cmd`، ثم زر **تثبيت**، ووافق على رسالة Windows. يأخذ من دقيقة إلى 3 دقائق.
4. افتح ديسكورد.

**لاحقاً:** تطبيق **Discord WARP** في قائمة ابدأ وبجانب الساعة: فحص، إصلاح، إيقاف مؤقت، البحث عن تحديث، تقرير مشكلة، إزالة.

**مع برامج VPN أخرى (من النسخة 1.4):** عندما تشغّل VPN آخر (NordVPN أو Windscribe أو Proton أو غيرها) يتوقف Discord WARP وحده ويعمل الديسكورد عبر ذلك الـ VPN، وعندما تفصله يعود Discord WARP وحده خلال ثوانٍ. لا تحتاج للضغط على أي زر. وإذا صار الاتصال بطيئاً يجرّب البرنامج وحده منفذ WARP آخر ويتذكر المنفذ الذي يعمل.

**التحديث:** زر "البحث عن تحديث" في التطبيق، أو ثبّت النسخة الجديدة فوق القديمة مباشرة. من النسخ 1.0 إلى 1.2: لم يعد Clash Verge مطلوباً.

**للإزالة:** زر "إزالة" في التطبيق، أو إعدادات Windows ← التطبيقات، أو `Uninstall-DiscordWARP.cmd`.
