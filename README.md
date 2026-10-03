# Wildbound

A quickfire 2D creature roguelite for iPhone: real-time card combat where your team is your deck, catching creatures mid-run, and an eight-floor run (about five minutes) ending at a boss that shifts element.

**[CLAUDE.md](CLAUDE.md) is the single source of truth**: the game design spec (rules, numbers, roster), the code map and the rules for changing code. This README only covers setup and shipping. Art packs: [docs/ART.md](docs/ART.md).

| Folder | What it is | Stack |
| --- | --- | --- |
| `game/` | The whole game. Runs in any browser. | Vite, TypeScript, PixiJS 8, GSAP |
| `app/` | The iOS app: a full-screen WebView that loads the built game, plus native saves and haptics. | Expo SDK 57, react-native-webview |

You build the iOS app in the cloud with EAS Build, so no Mac is required.

## Quick start

```bash
nvm use            # Node 22
npm run setup      # installs game/ and app/
npm run dev        # game in the browser at http://localhost:5173
```

- Switch art styles on the title screen, or with `?art=dusk` in the URL.
- `?export-pack` bakes the procedural creatures into PNGs plus anchor data. See docs/ART.md.

### On your iPhone (Expo Go, no build needed)

```bash
npm run app        # builds the game, embeds it, starts Expo. Scan the QR code.
```

### Live-reload the game on your phone while you edit

```bash
npm run dev                                                               # terminal 1
cd app && EXPO_PUBLIC_GAME_URL=http://<your-LAN-IP>:5173 npx expo start   # terminal 2
```

## Shipping to TestFlight

You need an Apple Developer account. Before the first build, change `ios.bundleIdentifier` in `app/app.json` (currently `com.taiga.wildbound`).

```bash
npm i -g eas-cli
cd app && eas login && eas build:configure   # first time only
npm run build:ios                            # from repo root: cloud build
npm run submit:ios                           # upload to TestFlight
```

EAS uploads the whole repo. The `eas-build-post-install` hook builds `game/` and embeds it, so the generated file is never committed.

## How the code is organised

See "Part 2: Engineering" in [CLAUDE.md](CLAUDE.md).

**Build output:** `npm run build` produces one self-contained `index.html` (about 1.2 MB), with fonts and pack images inlined, so the app works offline.
