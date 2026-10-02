# Wildbound

A quickfire 2D creature roguelite for iPhone. Cards play in real time, energy refills on its own, wild creatures can be caught mid-fight, and a run is eight floors (about five minutes) ending at a boss that shifts element.

**The art style is swappable.** Creatures, background and pedestals come from an *art style*. Two ship today:
- **Sticker:** procedural outlined vector creatures on a moonlit night.
- **Dusk:** an image pack (PNG creatures plus a sunset palette).

Drop in a folder of AI-generated art and it becomes a third. See [docs/ART.md](docs/ART.md).

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

```
game/src
├── main.ts                 boot + frame loop
├── core/                   no rendering here
│   ├── data.ts             ← content & balance: elements, creatures, cards, constants
│   ├── platform.ts         storage + haptics (browser vs. native bridge)
│   ├── audio.ts            WebAudio synth SFX
│   └── util.ts
├── render/                 style-independent rendering
│   ├── app.ts              Pixi app, world layers, effect textures
│   ├── layout.ts           HUD-aware stage layout (unit U, positions)
│   ├── actor.ts            on-screen creature: movement, squash, flash; holds the style's art
│   ├── stage.ts            current style's scene + pedestals, arena tint
│   ├── particles.ts        2,200-sprite pool, element bursts, rings, bloom
│   └── fx.ts               damage numbers, banners, shake, hit-stop
├── art/                    ← everything that is "the look"
│   ├── types.ts            ArtStyle / CreatureArt / SceneArt / PedestalArt contracts
│   ├── registry.ts         list of styles, active style, persistence
│   ├── shared/painter.ts   palette-driven procedural scene + pedestal
│   ├── sticker/            procedural vector style
│   ├── sprite/             image-pack style (manifest + PNG/WebP)
│   └── packs/<id>/         one folder per image pack (auto-discovered)
├── game/                   rules & flow (talks to Actors, never to art)
│   ├── state.ts  battle.ts  run.ts  ui.ts
└── tools/exportPack.ts     bake procedural art into a sprite pack
```

**The bridge:** the game calls `store` and `haptic()` from `core/platform.ts`.
- In a browser, these use `localStorage` and skip haptics.
- In the app, they post messages to `app/src/bridge.ts`, which uses AsyncStorage and expo-haptics.

**Build output:** `npm run build` produces one self-contained `index.html` (about 1.2 MB), with fonts and pack images inlined, so the app works offline.
