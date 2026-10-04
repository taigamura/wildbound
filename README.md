# Wildbound

A quickfire HD-2D creature roguelite for iPhone: real-time card combat where your team is your deck, an eight-floor run (about five minutes) ending at a boss that shifts element, and loot that upgrades your collection.

**[CLAUDE.md](CLAUDE.md) is the single source of truth**: the game design spec (rules, numbers, roster), the code map, the rules for changing code and the release process. This README only covers setup.

| Folder | What it is | Stack |
| --- | --- | --- |
| `godot/` | The game. | Godot 4.7.2, GDScript, Mobile renderer |
| `game/`, `app/` | Legacy web version (PixiJS in an Expo WebView), kept as the port's reference. | TypeScript, Expo SDK 57 |

## Quick start

Install [Godot 4.7.2](https://godotengine.org/download) (standard, not .NET) and put `godot` on your PATH.

```bash
godot --path godot -e                     # open the editor
godot --path godot                        # run the game (portrait 390×844)
godot --headless --path godot --script res://tests/test_core.gd   # logic tests
```

## Shipping to TestFlight

Builds run on a Mac build server over SSH and are submitted from this machine with `eas submit`. One-time: download the signing credentials with `cd app && npx eas-cli@24.10.0 credentials -p ios` (production → credentials.json → Download). Then:

```bash
scripts/ship-ios-godot.sh --no-submit   # signed ipa, no upload
scripts/ship-ios-godot.sh               # build, submit, bump godot/ios/build-number.txt
```

Details: CLAUDE.md, "Releasing".
