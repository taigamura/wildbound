# CLAUDE.md

**This file is the single source of truth for Wildbound:** what the game is (design spec), how the code is laid out, and the rules for changing it. If code and this file disagree, one of them is a bug; fix whichever is wrong and keep them in sync in the same change. `README.md` covers setup and shipping only. `docs/ART.md` is the how-to for making art packs, and it follows the art rules here.

All numbers below are **starting values**. They live in `game/src/core/data.ts` (`BAL` and the roster) and are tuned by playing. When you change a number there, change it here too.

---

# Part 1: Game design (MVP)

Portrait iOS creature roguelite. Real-time card combat, catching creatures mid-run, about 5-minute runs, one daily pack.

## 1. Pillars
1. **Frantic, readable combat.** Cards can be played at any time. The enemy telegraphs; you react.
2. **Your team is your deck.** Catching a creature *is* deckbuilding.
3. **Instant restart.** From death, to results, to a new run takes under 2 seconds of taps.
4. **Collection gives options, not power.** Every creature starts each run at the same strength. There is no leveling.
5. **Small asset budget.** One still image per creature. All motion comes from code (tweens, squash and stretch, particles).

## 2. Core loop
```
Daily pack (1 creature) → pick a starter → 8-floor run → catch & upgrade → win/lose → keep catches + Essence → spend Essence on loadouts → repeat
```

## 3. Elements
Loop: `Ember → Thorn → Volt → Tide → Ember` (each beats the next).

| Matchup | Damage |
|---|---|
| Attacker beats defender | ×1.5 |
| Defender beats attacker (a "resist") | ×0.66 |
| Not adjacent (Ember↔Volt, Thorn↔Tide) | ×1.0 |

Each element owns one status:

| Element | Status | On an enemy | On your creature | Duration |
|---|---|---|---|---|
| Ember | **Burn** | 2 damage/s | 2 damage/s | 4s |
| Tide | **Soak** | takes +25% damage | takes +25% damage | 4s |
| Thorn | **Root** | intent bar fills 40% slower | while it is lead, energy regenerates 40% slower | 3s |
| Volt | **Shock** | resets the intent bar (cancels the wind-up). Can't re-Shock the same target for 6s | resets your chain and puts swapping on a 1s cooldown | instant |

- One status per target; a new one replaces the old. Shock is instant and doesn't occupy the slot.
- Your cards apply statuses to the enemy. **Enemy heavy attacks apply their element's status** to the creature they hit. Normal attacks don't. Perfect Swaps avoid it.
- Status-card upgrades (+30% effect) lengthen the duration by 30%.

## 4. Combat

### 4.1 Layout (portrait)
- **Top:** enemy plate (HP bar, intent bar, statuses). During a heavy wind-up, a large element icon and the attack's name appear over the enemy.
- **Middle:** enemy and your lead creature. The chain counter floats beside your lead.
- **Bottom (thumb zone):** lead plate, 2 bench portraits, Evolve and Capture buttons (when available), energy bar, a hand of 4 cards.

### 4.2 Lineup
- The party holds **up to 6** creatures. The **lineup** is 3 of them: 1 lead and 2 bench.
- The **deck** is the lineup's *equipped* cards only: 3 creatures × 3 cards (Strike / Skill / Signature, as set in each creature's loadout, §16).
- Party members outside the lineup contribute no cards and don't fight.
- The party screen (set lineup and lead) opens automatically after a catch, and from the map's **Lineup** button at any time. It is never forced otherwise (pillar 3).

### 4.3 Energy and hand
- Energy regenerates **1/s**, **cap 10**. A fight starts with 3.
- Hand of **4**. Playing a card immediately draws the next one. The deck cycles: the discard pile reshuffles when the draw pile is empty. With fewer than 4 cards in the deck (floor 1, solo starter), the extra slots stay empty.
- Cards can be played any time, including during wind-ups. There is no global cooldown.
- **Cards belong to a creature.** Each card shows its owner's mini-portrait and element colour, and uses the owner's element.
  - Playing a lead card fires it normally.
  - Playing a **bench creature's card swaps that creature in, then fires the card.** The swap costs nothing extra but starts the shared swap cooldown. **While swapping is on cooldown, bench cards can't be played** (they dim).
  - Cards of knocked-out creatures leave the hand and the deck for the rest of the fight.
- "Self" on a card means its owner, which is always the lead when it fires. "Team" means every living lineup member.

### 4.4 Swapping
- Tap a bench portrait to swap for **1 energy**. **1s cooldown**, shared with card swaps.
- When the lead is knocked out, the healthiest bench creature auto-swaps in for free.
- Shields and statuses stay on a creature when it is benched (shields keep decaying).

### 4.5 Auto-attack
The lead auto-attacks every **1.5s** for **2** damage, element multipliers applied. The chain doesn't apply.

### 4.6 Enemy behaviour
- Intent bar fills over **3s** for a normal attack (÷ species speed).
- **Every 3rd attack is heavy:** wind-up **+2s**, shows a large element icon and the attack's name, deals **2.5×**, and applies its element's status.
- Enemies attack in their own element (exceptions: Warden, Noctyrm).
- Enemy damage: base **5** × species attack × floor scaling (§6).

### 4.7 Perfect Swap (the skill ceiling)
Swap (either way) to a creature that **resists** the incoming element during the **last 0.4s** of a heavy wind-up:
- you take **0** damage and no status
- **50%** of the attack is reflected at the enemy
- you're refunded **2** energy
- **0.3× speed for 0.5s**, 120ms hit-stop, flash, heavy haptic, "PERFECT" popup.

A swap outside the window is a normal swap. During a heavy wind-up, bench portraits that resist the incoming element show a shield marker.

### 4.8 Chain meter
- A card played within **1.5s** of the previous card raises the chain by 1.
- Each step: **+10%** card damage, max **+50%** (5 steps).
- Resets after a 1.5s gap. The counter pulses in its last 0.5s.

### 4.9 Win and lose
- **Win:** enemy at 0 HP, or a successful capture. A wild that flees (§5) also ends the fight, with no reward.
- **Lose:** all lineup creatures knocked out. **The run ends.**
- After every fight, knocked-out creatures revive at **25%** HP. HP otherwise carries over; shields and statuses clear. Healing comes from Springs, Heal rewards and cards.

## 5. Capture
- The Capture button activates when a wild enemy is **below 40%** HP.
- Each attempt costs **1 Capture charge**. A run starts with **2**.
- **Odds:** `50% + (40% − enemy HP%) + 15% if the enemy has a status + 20% if enraged`, capped at **95%**. The button shows the odds.
- **On failure:** the creature breaks free and **enrages**: +30% attack speed, and the +20% capture bonus above.
- **Flee timer:** once a wild first drops below 40%, it flees after **15s** unless caught or defeated. The timer is shown on its plate.
- Alphas, the Warden and the boss **can't be captured**.
- Party full (6): choose one to release, or let the catch go.
- Caught creatures join at **60%** HP, with their own 3 cards.

## 6. Run structure
8 floors across 2 biomes. Each floor offers **2–3 nodes**.

| Floor | Biome | Nodes |
|---|---|---|
| 1–3 | A | 2 Wilds of different elements, plus 50%: Spring or Alpha (no Alpha on floor 1) |
| 4 | A | **Warden** (fixed) |
| 5–7 | B | Wild, Alpha, plus 60%: Spring |
| 8 | B | **Noctyrm**, the boss (fixed) |

| Node | What it is |
|---|---|
| **Wild** | A capturable creature from the biome's spawn pool (can be one you don't own) |
| **Alpha** | +50% HP, +25% damage, can't be captured. Its reward gives **2 picks** |
| **Spring** | Heal the whole party to 100% (reviving KOs) and +1 Capture charge |
| **Warden** | Mid-run boss (§8) |
| **Boss** | Noctyrm (§8) |

**Enemy scaling:** wild HP = `90 × (0.6 + 0.4 × speciesHP / 55) × (1 + 0.15 × (floor − 1))`. Damage ×`(1 + 0.10 × (floor − 1))`. Biome B wilds drawn from the Biome A pool scale as if 2 floors higher.

## 7. Rewards (after every non-boss win that isn't a flee)
Pick **1 of 3**: **Upgrade a card**, **Heal** (40% max HP to the whole party, reviving KOs), or **+1 Capture charge**. Alphas give 2 picks; repeats are allowed.

- **Upgrade:** choose any equipped card in your party, then **+30% effect** or **−1 cost** (min 0). Each card can be upgraded once. A card with no number to scale (e.g. Static, Flicker) offers only −1 cost.
- Upgrades belong to the card, so they leave with a released creature.

## 8. Warden and Boss
- **Warden: Gravewood** (floor 4), a Thorn apex. **300 HP.** Every 3rd attack is heavy, alternating **Bramble Crush** (Thorn) and **Wildfire Roar** (Ember), so each cycle needs at least one swap read.
- **Noctyrm** (floor 8): **270 HP.** Shifts element every **7s**. Its heavy (**Eclipse Volley**, three projectiles) uses its *current* element.

## 9. Evolution
- **Whatever creature you start the run with** has an **Evolution meter**. It fills with damage dealt by that creature (cards, auto-attacks, its Burns): **150** to fill.
- When full, an **Evolve** button appears in the action row. (Not a portrait tap: tapping a bench portrait swaps.) **3 energy** to evolve mid-fight: 0.5s slow-mo, flash, burst, heavy haptic.
- Effects: **+50% max HP, then a full heal**; the **Signature card is upgraded** (stacks with a §7 upgrade); evolved art.
  - The 3 starters have named evolutions with their own Signature (§10). The named Signature replaces only the **default** Signature. If the starter has its alternate Signature equipped (§16), that card gets the Prime **×1.4 effect** instead.
  - Any other creature used as a starter becomes "Prime <name>", with its equipped Signature at **×1.4 effect**. This keeps non-starters a real choice (pillar 4).
  - If the active art style has no image for the evolved form, the base art is drawn at ×1.2 scale with a glow.
- Evolution lasts for the rest of the run only.

## 10. Roster (12 creatures + 3 evolutions)
Each creature has 3 card slots: **Strike / Skill / Signature**. Strike has one option; Skill and Signature each have the default and one alternate (unlocked with Essence, §16). Each creature also has a built-in Trait (§16). HP is max HP at run start. Atk/Spd only affect it as an enemy.

"N dmg ×H" hits H times; each hit gets the chain bonus. "+N if Burned" (or Soaked, Rooted) adds N damage if the enemy has that status.

### Ember
| Creature | Role | HP | Strike | Skill | Alt Skill | Signature | Alt Signature | Trait |
|---|---|---|---|---|---|---|---|---|
| **Emberwick** ⭐ | Balanced | 50 | Peck (1): 6 dmg | Kindle (2): apply Burn | Flare Step (1): +1 energy, +1 chain | Wickflare (3): 14 dmg, +8 if Burned | Wildfire (3): 8 dmg, apply Burn, +1 chain | Afterglow |
| ↳ **Pyrowl** | | | | | | Crownflare (3): 20 dmg, +12 if Burned, apply Burn | | |
| **Cinderpip** | Glass cannon | 35 | Scorch (1): 7 dmg | Flicker (1): next card costs 1 less | Flare Up (1): +1 chain, take 2 | Flashfire (4): 24 dmg | Ember Barrage (3): 5 dmg ×3 | Quickfuse |
| **Kilnback** | Tank | 75 | Bash (1): 5 dmg | Hearth Shell (2): shield 12 | Forge (2): shield 6, next Strike ×2 | Slow Burn (3): apply Burn, shield 8 | Magma Ram (3): 16 dmg, take 4 | Bulwark |

### Tide
| Creature | Role | HP | Strike | Skill | Alt Skill | Signature | Alt Signature | Trait |
|---|---|---|---|---|---|---|---|---|
| **Bellspring** ⭐ | Sustain | 55 | Splash (1): 5 dmg | Drench (2): apply Soak | Tidecall (2): shield team 5 | Lantern Tide (3): 10 dmg, heal team 8 | Undertide (3): 14 dmg, +6 if Soaked | Ebb |
| ↳ **Lanternmere** | | | | | | Beacon Tide (3): 14 dmg, heal team 14 | | |
| **Puddlet** | Healer | 40 | Drip (1): 4 dmg | Mend (2): heal self 15 | Bubble (1): shield 7 | Spring Rain (4): heal team 12, cleanse team | Wellspring (3): heal team 6, +2 energy | Undercurrent |
| **Brinecrab** | Tank | 80 | Pinch (1): 6 dmg | Barnacle (2): shield 14 | Brace (1): next hit taken reflects 30% | Undertow (3): 12 dmg, apply Soak | Tidal Clamp (3): 10 dmg, shield 10 | Counterweave |

### Thorn
| Creature | Role | HP | Strike | Skill | Alt Skill | Signature | Alt Signature | Trait |
|---|---|---|---|---|---|---|---|---|
| **Truffmole** ⭐ | Control | 55 | Dig (1): 6 dmg | Tangle (2): apply Root | Burrow (2): shield 8, next Strike ×2 | Sporeburst (3): 12 dmg, heal self 6 | Rootquake (4): 16 dmg, apply Root | Deep Roots |
| ↳ **Morelord** | | | | | | Spore Bloom (3): 18 dmg, heal team 8 | | |
| **Brambat** | Drain | 40 | Nip (1): 5 dmg, heal self 2 | Thornveil (2): next hit taken reflects 50% | Hemlock (2): apply Root, heal self 6 | Leech Dive (3): 12 dmg, heal self 50% of damage | Thorn Storm (4): 8 dmg ×2, next hit taken reflects 30% | Thirst |
| **Mossling** | Support | 50 | Swat (1): 5 dmg | Overgrow (2): apply Root, shield 6 | Photosynth (2): heal team 5 | Canopy (3): shield team 8 | Strangle Vine (3): 10 dmg, +6 if Rooted | Overshade |

### Volt
| Creature | Role | HP | Strike | Skill | Alt Skill | Signature | Alt Signature | Trait |
|---|---|---|---|---|---|---|---|---|
| **Skiray** | Tempo | 45 | Zap (0): 3 dmg | Static (2): apply Shock | Tailwind (1): +2 chain | Gale Strike (3): 10 dmg, +1 chain | Arc Lash (3): 6 dmg, apply Shock | Relay |
| **Sparkit** | Glass cannon | 35 | Jolt (1): 7 dmg | Overcharge (1): +2 energy, take 4 | Supercharge (2): next Strike ×3 | Thunderclap (4): 22 dmg | Ball Lightning (3): 14 dmg, +1 chain | Live Wire |
| **Coilsnail** | Tank | 70 | Prod (1): 5 dmg | Capacitor (2): shield 10, next Strike ×2 | Grounding (2): shield 8, cleanse team | Discharge (3): damage equal to your shield, consuming it | Static Field (3): shield team 6, apply Shock | Grounded |

- **Shields** absorb damage until broken, and decay 20%/s once 3s have passed since they were last added to.
- **Spawn pools:** Biome A (floors 1–3): Cinderpip, Puddlet, Brambat, Skiray, Kilnback, Mossling. Biome B (5–7): Brinecrab, Sparkit, Coilsnail, plus the Biome A pool at +2 floors' scaling.

## 11. Collection and the daily pack
- **New install:** you own the 3 starters.
- **Daily pack:** one per day, resetting at **04:00 device-local time**. A card-flip reveal grants **1 creature you don't own**, random from the 9 non-starters. Once you own all 12, it grants a **shiny** of a random owned creature that isn't shiny yet (a hue-shift with a sparkle on entry). With everything shiny, it says so.
- **Starting a run:** pick any owned creature. It starts at its §10 stats with its saved loadout (§16).
- **End of run:** **Win:** every species caught this run joins the collection. **Loss:** keep **1** caught species of your choice. Every species caught this run that was already owned before the run converts to **+3 Essence** of its element (win or loss, §16).
- **Collection screen:** 12 slots; unowned are silhouettes. Tap any slot to see its cards and Trait. It is also the **loadout editor** for owned creatures (§16).
- **"Run again"** on the results screen restarts immediately with the same starter.
- **Persisted** (through `core/platform.ts` `store`): `owned`, `shiny`, `packDay`, `best`, `wins`, `starter`, `art`, `muted`, `essence`, `learned`, `loadout`.

## 12. Feel
- **Haptics:** light on card play, medium on a hit landing, heavy on a Perfect Swap, a capture success or an evolution.
- **Hit-stop:** 60ms on heavy and super-effective hits, 120ms on a Perfect Swap.
- **Damage numbers:** coloured by element, larger for super-effective hits, "RESIST" label on resisted hits.

## 13. Art and asset budget
12 creature stills, 3 evolution stills, 1 Warden, 1 boss, 2 biome backgrounds = **19 images**. Element icons and card frames are drawn in code. Shinies are a filter. Missing images fall back to the procedural Sticker look (evolutions fall back to scaled base art with a glow, §9).

## 14. Out of scope (later)
Shop, events, rival tamers, tamer cards, eggs, Warden part-breaking, crafting beyond Essence unlocks (§16), more than one alternate per card slot, sightings-based packs, evolutions for non-starters beyond "Prime", a second Warden, ranked mode and leaderboards, a daily seeded run, cosmetic card frames, monetization.

## 15. Open tuning questions (decide by playing)
- Does bench-card swapping churn the lead so much that Perfect Swaps happen by accident? Fallback: bench cards fire from the bench without swapping, and only portrait taps swap.
- Wild spawns include unowned species, so most players will own everything within a few days and the pack becomes shinies-only. Fallback: spawn only owned species and make the pack the only way to unlock new ones.
- Essence earn rate: target **1–2 unlocks per run**. Levers: `BAL.essWild`/`essAlpha`/`essCatch`/`essDupe`, `moveCost`, `traitCost`.
- Do the chain Traits (Live Wire, Quickfuse, Relay) stack too strongly when socketed together? Levers: raise `BAL.livewireChain`, or allow only one chain Trait per lineup.
- Late-floor difficulty with no leveling: watch floor 6–8 death rates. The levers are `BAL.hpPerFloor`/`dmgPerFloor`, Spring frequency and Heal reward size.

## 16. Loadouts, Essence and Traits
Collection gives options, not power (pillar 4): every alternate is a sidegrade, and nothing raises a creature's numbers.

### 16.1 Loadouts
- Per creature: **Skill** (default or alternate), **Signature** (default or alternate), and a **Trait** socket. Strike has one option. Alternates are in §10.
- Loadouts are saved per species and edited only on the **Collection screen**, never mid-run, so "Run again" stays one tap (pillar 3).
- A creature uses its saved loadout whenever it joins the party (starter or catch). It's fixed for that creature for the rest of the run.
- Locked or missing choices fall back to the default.
- Unlocking a card equips it; learning a Trait sockets it in the creature being viewed (one tap fewer).

### 16.2 Traits
- Every creature has a built-in Trait in its socket. **The socket is never empty.**
- Once a Trait is **learned**, other creatures can socket it. A learned Trait sits in **only one** other creature at a time: socketing it elsewhere returns the previous holder to its built-in Trait. The creature it's built into always keeps it.
- A learned Trait is usable only while its source creature is owned.
- "It" / "its" means the creature holding the Trait.

| Trait | Built into | Effect |
|---|---|---|
| **Afterglow** | Emberwick | When its Burn on the enemy ends, +1 energy |
| **Quickfuse** | Cinderpip | Its first card each fight costs 0 |
| **Bulwark** | Kilnback | Its shields start decaying **3s** later |
| **Ebb** | Bellspring | Heals **4** when swapped out |
| **Undercurrent** | Puddlet | Its heals also cleanse whoever they heal |
| **Counterweave** | Brinecrab | A Perfect Swap into it also fires its Strike for free |
| **Deep Roots** | Truffmole | Root it applies lasts **+1.5s** |
| **Thirst** | Brambat | Its Strikes heal it for **30%** of their damage |
| **Overshade** | Mossling | When it shields itself, the weakest teammate gets **half** |
| **Relay** | Skiray | After a card swaps it in, your next card costs 1 less |
| **Live Wire** | Sparkit | The first time its card reaches chain **3+**, +1 energy |
| **Grounded** | Coilsnail | Can't be Shocked; a Shock on it gives +1 energy instead |

### 16.3 Essence
One persisted currency split into the 4 elements. The end-of-run screen shows the Essence earned.

| Source | Essence |
|---|---|
| Defeat a Wild | **+1** of its element |
| Catch a creature | **+2** of its element (instead of the Wild amount) |
| Defeat an Alpha | **+2** of its element |
| Defeat the Warden | **+3** Thorn and **+3** Ember |
| Defeat Noctyrm | **+2** of every element |
| A wild flees | nothing |
| End of run: each species caught that was already owned before the run | **+3** of its element (win or loss) |

| Spend | Cost | Requires |
|---|---|---|
| Unlock an alternate card | **5** Essence of the creature's element | the creature is owned |
| Learn a Trait | **8** Essence of its source creature's element | the source creature is owned |

Unlocks are permanent.

---

# Part 2: Engineering

## Session start: catching up
A SessionStart hook (`.claude/hooks/session-context.sh`, registered in `.claude/settings.json`) prints the last 10 commits and any uncommitted changes into context automatically.
1. **Recent work:** that hook output. The commit messages say what changed and why. If it's missing, run `.claude/hooks/session-context.sh` yourself.
2. **Current state:** read "Releasing" below for what has shipped and how builds work. That section is the authority for anything git can't see (TestFlight uploads, credentials, the build server).
3. **Uncommitted work:** also in the hook output.

Keep both up to date: write commit bodies that explain *why*, and edit "Releasing" in the same change whenever release state changes (a new upload, a credentials change, a pipeline change).

## What this is
A PixiJS web app (`game/`) shipped inside an Expo WebView shell (`app/`). iOS builds run on EAS, so no Mac is needed.

**The art style is expected to change.** All visuals that define the look go through `game/src/art/` (see `docs/ART.md`). Gameplay code must stay art-agnostic.

## Commands
- `npm run dev`: game at http://localhost:5173 (`?art=<id>` picks a style; `?export-pack` bakes creature PNGs)
- `npm run typecheck`: game + app
- `npm run build`: build the game and embed it into the app (`app/src/game-html.generated.ts`, gitignored)
- `npm run app`: Expo dev server (Expo Go works)
- `cd app && npx expo export --platform ios`: proves the iOS bundle compiles (CI runs this)

## Where things live
- Balance and content: `game/src/core/data.ts`. `BAL` holds every tuning number; `SPECIES` holds the roster and cards (each slot is a list: `[default, ...alternates]`); `TRAITS` holds the Trait definitions.
- Combat, statuses, Perfect Swap, chain, capture, evolution, Trait effects: `game/src/game/battle.ts`.
- Map, nodes, rewards, upgrades, party/lineup, end of run, title, Collection and the loadout editor: `game/src/game/run.ts`.
- Collection, daily pack, Essence, unlocks, saved loadouts and persisted progress: `game/src/game/meta.ts`.
- Run state and card resolution helpers (deck building, equipped and upgraded card stats): `game/src/game/state.ts`.
- DOM HUD and card rendering: `game/src/game/ui.ts`.
- On-screen creatures: `render/actor.ts` (the `Actor` class). Gameplay only ever uses Actors.
- Art: `art/types.ts` (contracts), `art/registry.ts` (active style), `art/sticker/`, `art/sprite/`, `art/packs/<id>/`.
- Host bridge: `core/platform.ts` ↔ `app/src/bridge.ts`. Keep the message types in sync.

## Rules
- **Art boundary:**
  - `game/*` and `render/particles.ts`/`fx.ts` must not import from `art/sticker` or `art/sprite`.
  - Go through `getStyle()` or an `Actor`.
  - A new visual concept that should vary by style becomes a new optional member of `ArtStyle`, with a style-independent default. Existing ones: `scene(biome)`, `has(species)` (used for the evolution fallback).
- **Species keys** are the lowercase creature names (`emberwick`, `pyrowl`, `warden`, `noctyrm`). Art packs key images by them.
- **Art space:** facing right, feet at (0,0), about 100 units tall for a size-1 creature, head around y = -56. `Actor` scales art space by `U / 56 * species.size`.
- **Stale callbacks:** `S.tok` is bumped when a battle or run ends. Every delayed callback (gsap `delayedCall`/`onComplete`, `setTimeout`) captures `tok` and bails if it changed.
- **Timing:** use gsap for time-based effects so they respect hit-stop and slow-mo (`gsap.globalTimeline.timeScale`).
- **Units:** layout is in units of `U` (px, from `render/layout.ts`). `emit()` speeds, sizes and gravity are in U.
- **Input:** card taps use `pointerdown`, not `click`.
- **Storage and native calls:** never touch `localStorage` or `window.ReactNativeWebView` outside `core/platform.ts`.
- **Native modules:** Expo SDK 57. Install with `npx expo install` so versions match the SDK.
- **Bundle size:** pack images are inlined into the single-file build, so keep them small (WebP, about 512 px).

## Releasing (iOS / TestFlight)
- **Identity:** bundle ID `com.taiga.wildbound`, App Store Connect app ID `6818680785`, EAS project `@taigamura/wildbound` (ID in `app/app.json`). The version is `expo.version` in `app/app.json`; EAS manages build numbers remotely (`appVersionSource: remote`, auto-increment), so `ios.buildNumber` in `app.json` is ignored.
- **Credentials live on EAS:** distribution certificate, provisioning profile and the App Store Connect API key. No Apple login is needed for routine builds and submits, so they can run with `--non-interactive`. If submit returns `401 NOT_AUTHORIZED`, the stored ASC key is bad: remove it via `eas credentials -p ios` (App Store Connect: Manage your API Key) and let the next interactive `eas submit` generate a new one.
- **Normal path: `/ship-ios`** (config in `.claude/ship.json`). Commit, PR and merge, then a local EAS build on the Mac build server (`taigamura-MBP`, 192.168.50.175, repo at `~/dev/wildbound`, builds from `app/`), copy the `.ipa` back, and submit from this machine. If a local build fails with keychain `error code: 36`, unlock the Mac's login keychain in a terminal there. **Currently blocked:** the Mac's Xcode 26.3 fails to compile `expo-modules-jsi` (`RuntimeScheduler.h`: "cannot be annotated with SWIFT_RETURNS_RETAINED"), an Expo SDK 57 / Xcode mismatch unrelated to game code. Use the cloud fallback until an Expo patch or an Xcode change fixes it.
- **Fallback: EAS cloud build** from the repo root: `npm run build:ios`, then `npm run submit:ios`. `app/eas.json` sets `ascAppId` in the production submit profile, which `--non-interactive` submits require.
- **History** (newest first; `/ship-ios` adds a line per upload via `releaseLog` in `.claude/ship.json`; add one by hand for any other upload):
  - 2026-10-03: v0.2.0 build 4 (EAS cloud build `bbc5de69`, commit `ccfaec7`, submission `b282dadf`) uploaded to TestFlight. Loadouts, Traits and Essence (§16). The first `/ship-ios` run: commit, PR #2 and merge worked; the local Mac build failed (see above), so it fell back to the cloud.
  - 2026-10-03: `/ship-ios` configured.
  - 2026-10-03: v0.2.0 build 2 (EAS cloud build) uploaded to TestFlight. This is the MVP design build.

## Verifying changes
- Run `npm run typecheck` and `npm run build`.
- Play a run in the browser at 390×844 in every art style (switch on the title screen).
- In dev, `window.__wb` is the run state; `__wb.debug` has helpers (see `main.ts`), including `__wb.debug.essence(n)` (grant Essence) and `__wb.debug.trait(key)` (socket a Trait on the lead).
- For app-side changes, also run the iOS export.
