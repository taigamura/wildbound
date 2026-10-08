# CLAUDE.md

**This file is the single source of truth for Wildbound:** what the game is (design spec), how the code is laid out, and the rules for changing it. If code and this file disagree, one of them is a bug; fix whichever is wrong and keep them in sync in the same change. `README.md` covers setup and shipping only. `docs/UI-QUEUE.md` lists UI follow-ups left over from the redesign. `docs/HD2D.md` is the ChatGPT template and normalizer guide for HD-2D sprites; it follows the art rules here. `godot/CONTRACT.md` is the module contract from the Godot port.

All numbers below are **starting values**. They live in `godot/core/data.gd` (`BAL` and the roster) and are tuned by playing. When you change a number there, change it here too.

---

# Part 1: Game design (MVP)

Portrait iOS creature roguelite. Real-time card combat, creatures collected from packs (one free daily pack, more earned by winning fights), loot that upgrades them between runs, about 5-minute runs.

## 1. Pillars
1. **Frantic, readable combat.** Cards can be played at any time. The enemy telegraphs; you react.
2. **Your team is your deck.** Picking your three creatures before a run *is* deckbuilding.
3. **Instant restart.** From death, to results, to a new run takes under 2 seconds of taps.
4. **Collection and loot give lasting progress.** Packs add creatures and copies of them (options: more copies unlock alternate cards); dungeon loot buys permanent upgrades (power), and Essence learns Traits (options). There is no evolution: each creature is unique and has one form.
5. **Small asset budget.** One still image per creature. All motion comes from code (tweens, squash and stretch, particles).

## 2. Core loop
```
Packs (daily free, earned on the pack meter, or bought; pick 1 of 3) → pick a team of up to 3 → 8-floor run → loot and pack points every win → win/lose (both are kept either way) → open packs, upgrade creatures, shop, set loadouts → repeat
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
| Thorn | **Root** | intent ring fills 40% slower | while it is lead, energy regenerates 40% slower | 3s |
| Volt | **Shock** | resets the intent ring (cancels the wind-up). Can't re-Shock the same target for 6s | resets your chain and puts swapping on at least a 1s cooldown | instant |

- One status per target; a new one replaces the old. Shock is instant and doesn't occupy the slot.
- Your cards apply statuses to the enemy. **Enemy heavy attacks apply their element's status** to the creature they hit. Normal attacks don't. Perfect Swaps avoid it.
- Status-card upgrades (+30% effect) lengthen the duration by 30%.

## 4. Combat

### 4.1 Layout (portrait)
- **Top:** the enemy plate in one window: an intent ring that fills over the wind-up, the name, status tags, the element chip and an HP bar with the number outside. Under it, a strip that is always reserved: during a heavy wind-up it shows a banner with the attack's name, its element, the seconds left and which element resists it. Nothing is drawn over the enemy.
- **Middle:** enemy and your lead creature. The chain counter floats beside your lead.
- **Bottom (thumb zone):** a party rail (the lead's face, name, HP, Trait and statuses on the left; round bench portraits on the right), then the energy crystal beside a hand of 4 cards.
- **The hand is a fan**, held like real cards: they overlap and tilt around a pivot below the screen (about ±4° and ±12° for 4 cards, outer cards slightly lower). Only cards that exist are fanned, so a short deck leaves no gaps.
- **Quit:** a button in the battle HUD (beside mute) and on the map (beside the title). There is no pause: the first tap arms it for 2s, the second ends the run as a loss ("Retreated"). Loot already banked is kept.

### 4.2 Lineup
- Before a run, the **Team** screen (opened from the title's team pill or the dock's Team cell, never the title itself) picks the team: **up to 3** owned creatures. The title shows the current team and Start. The party *is* this lineup for the whole run (no creatures join or leave mid-run). The last team is remembered (saved on every change).
- **Faces, coloured like the cards.** The three lineup slots and the grid of owned creatures (four wide) are card-style tiles: the creature's face in a card face window washed and framed in its element colour, its name under it. Slot 1 is the lead ("1 ★", "Lead"); a creature in the team carries its slot's number badge in the grid and a gold outline.
- **Pick a slot, then a creature.** One slot is always the cursor: a pulsing white ring and "Choosing". Tapping a creature in the grid puts it in that slot: a teammate trades places with whoever is there (nobody leaves), any other creature replaces the slot's creature (or fills the empty slot). Tapping a slot moves the cursor there; the ✕ on a slot removes its creature (one always stays). The cursor starts on the first empty slot, or the lead when the team is full, and moves to the next empty slot after each fill. The hint under the lineup names exactly what the next tap does ("Tap a creature for slot 2 instead of Bellspring"). The changed slot pops, and the creature on the stage is the one just placed.
- Beside the title, element chips show the team's element mix (e.g. Ember ×2, Tide ×1). The sheet is kept short so the creature on the stage stands near the front of the diorama.
- The **deck** is the lineup's *equipped* cards: up to 3 creatures × 3 cards (Strike / Skill / Signature, as set in each creature's loadout, §16).
- The party screen (choose the lead) opens from the map's **Lineup** button at any time. It is never forced (pillar 3).

### 4.3 Energy and hand
- Energy regenerates **1/s**, **cap 10**. A fight starts with 3. It shows as a crystal orb beside the hand: the number inside, one pip per point around the rim, filling like liquid as it regenerates.
- Hand of **4**. Playing a card immediately draws the next one. The deck cycles: the discard pile reshuffles when the draw pile is empty. With fewer than 4 cards in the deck (floor 1, solo starter), the extra slots stay empty.
- Cards can be played any time, including during wind-ups. There is no global cooldown.
- **Hold to read, slide to scrub, swipe up to play.** A touch lifts the card under the finger slightly and shows it enlarged in the middle of the stage, between the enemy plate and the party rail, so the bench stays visible. Sliding sideways moves the magnification along the fan, like picking a card from a held hand. Swiping up plays the magnified card (up more than 40% of its height, or released moving up fast after 15%). Once the swipe passes 12% of the card's height it locks to that card and the card follows the finger; dragging back down returns to scrubbing. Releasing without a swipe puts the card back. A card that can't be played can still be magnified; swiping it shakes it and it snaps back.
- **Each card belongs to its owner.** The deck is built from each lineup creature's equipped cards (§4.2); a card's **owner** is the creature that brought it, and the card has the owner's element. The card face (the "Crystal Foil" card) shows:
    - **Cost** as a rail of energy crystals down the left edge (the number under them from 3 up). Crystals you can't afford yet are red outlines; a −1 cost upgrade leaves a hollow crystal.
    - **The owner's face only**, framed in the element's colour (alive or knocked out; there is no shared split window).
    - **Foil by slot:** Strike plain, Skill crosshatched, Signature a gold double frame with a moving sheen.
    - Statuses (Basic, Strong, upgraded, can't afford) get their own strip under the rules text.
  - **What the lead can do with a card** depends on who owns it:
    - **The lead owns it:** it plays in full: its printed cost, its effect, the lead's permanent Power and Spirit (§5.2) and its Trait (Quickfuse counts its first card, Thirst heals it on its Strikes, and so on). The card's text, slot and in-run upgrade (§7) come from the card.
    - **Same element, but the owner is benched or knocked out:** the card plays as a **basic hit**. It costs **1** energy whatever its printed cost and deals **4** × the lead's Power in the lead's element (chain bonus and element multipliers apply). It raises the chain like any card, but has no card effects, triggers no Traits, neither uses nor applies the discount, and isn't the lead's "played" card (Quickfuse). The face shows the cost as 1 crystal, the rules text dimmed, and a "BASIC n" strip with the real damage (Power included).
    - **Another element:** it can't be played. It stays in the hand, dimmed with a swap chip in its element's colour; swiping it shakes it and a toast names the owner ("Swap to Emberwick to play this").
    - **Dead:** no living lineup member shares its element. Dead cards **stay in the deck**, greyed out with the owner's face under "KO". Swiping one up discards it for **1** energy and draws the next card (no chain, Trait or discount effects).
  - Each bench portrait counts the hand cards it **owns** that aren't fully playable right now (swap to it to fire them in full); a knocked-out creature counts nothing. Playing a card never swaps. Deciding when to swap (and whether a basic hit now beats the full card later) is the strategy.
- "Self" on a card means the lead that plays it (the owner, since only the owner fires card effects). "Team" means every living lineup member.

### 4.4 Swapping
- Swapping is **only** by tapping a bench portrait. It is free but has a **6s cooldown**. Bench portraits are 56px circles showing the creature's face inside an HP ring; the cooldown is a dark wedge with the seconds left, and the portrait pops when swapping is ready. An element-coloured chip at its lower right counts the hand cards it owns that it would fire in full once it leads (none while it's knocked out).
- When the lead is knocked out, the healthiest bench creature auto-swaps in for free; this ignores and does not start the cooldown.
- Shields and statuses stay on a creature when it is benched (shields keep decaying).

### 4.5 Auto-attack
The lead auto-attacks every **1.5s** for **2** damage, element multipliers applied. The chain doesn't apply.

### 4.6 Enemy behaviour
- The intent ring fills over **3s** for a normal attack (÷ species speed).
- **Every 3rd attack is heavy:** wind-up **+2s**, shows the heavy banner under the enemy plate (name, element, seconds left, who resists) while the intent ring draws thicker in the heavy's element, deals **2.5×**, and applies its element's status.
- Enemies attack in their own element (exceptions: Warden, Noctyrm).
- Enemy damage: base **5** × species attack × floor scaling (§6).

### 4.7 Perfect Swap (the skill ceiling)
Swap (either way) to a creature that **resists** the incoming element during the **last 0.4s** of a heavy wind-up:
- you take **0** damage and no status
- **50%** of the attack is reflected at the enemy
- you're refunded **2** energy
- **0.3× speed for 0.5s**, 120ms hit-stop, flash, heavy haptic, "PERFECT" popup.

A swap outside the window is a normal swap. During a heavy wind-up, bench portraits that resist the incoming element show a shield badge and a cyan glow.

### 4.8 Chain meter
- A card played within **1.5s** of the previous card raises the chain by 1.
- Each step: **+10%** card damage, max **+50%** (5 steps).
- Resets after a 1.5s gap. The counter pulses in its last 0.5s.

### 4.9 Win and lose
- **Win:** enemy at 0 HP. Every win drops loot (§5.1) and pack points (§11).
- **Lose:** all lineup creatures knocked out. **The run ends.**
- **Victories don't heal.** After a fight, HP carries over and knocked-out creatures stay down at 0 HP until a Spring or a Heal reward revives them; shields and statuses clear. If the lead is down, the healthiest living creature leads the next fight. Healing comes from Springs, Heal rewards and cards.

## 5. Loot, upgrades and the item shop
Creatures come only from packs (§11). Dungeons are for **loot**: **gold** and three materials, **Sword**, **Orb** and **Jewel**. Loot is banked (persisted) the moment it drops, so it is kept whether the run is won or lost.

### 5.1 Loot drops
| Win | Gold | Materials |
|---|---|---|
| Wild | **8–12** × `(1 + 0.15 × (floor − 1))` | **35%** chance of 1 random |
| Alpha | double the Wild gold | **1** random, guaranteed |
| Warden | **40** | **2** random |
| Noctyrm | **80** | **3**: one of each |
| Win the run | **+50** | |

The reward screen shows the fight's loot; the end-of-run screen shows the run's total. A **Scavenge** reward pick (§7) adds 1 random material.

### 5.2 Permanent upgrades
Every owned creature has three upgrade tracks, levels **0–5**, bought on the Collection screen and kept forever. They apply when the creature joins a run.

| Track | Material | Per level |
|---|---|---|
| **Power** | Sword | **+8%** damage of the cards it plays (including bonus damage and Discharge) and auto-attack damage |
| **Spirit** | Orb | **+10%** shield and heal amounts of the cards it plays |
| **Vitality** | Jewel | **+8%** max HP |

Level n → n+1 costs **(n+1)** of the track's material **+ 20 × (n+1)** gold (so level 1 is 1 material + 20 gold; level 5 is 5 + 100).

### 5.3 Item shop
Reached from the title screen and the end-of-run screen. Shows gold and material counts.
- **Buy:** a Sword, Orb or Jewel for **30** gold each; a **creature pack** for **150** gold (pick 1 of 3, like any pack, §11). If a rolled pack is still waiting for its pick, the shop's pack button opens that one instead, free.
- **Sell:** any material for **15** gold.

## 6. Run structure
8 floors across 2 biomes. Each floor offers **2–3 nodes**.

| Floor | Biome | Nodes |
|---|---|---|
| 1–3 | A | 2 Wilds of different elements, plus 50%: Spring or Alpha (no Alpha on floor 1) |
| 4 | A | **Warden** (fixed) |
| 5–7 | B | Wild, Alpha, plus 60%: Spring |
| 8 | B | **Noctyrm**, the boss (fixed) |

The map is a short trail: this floor's nodes are medallions on branching paths, with the next floors fading up toward the Warden or Noctyrm. The first medallion starts selected and its details (gold range and material chance for Wilds and Alphas) show in a strip below; tapping another selects it, and a second tap or **Travel** goes there.

| Node | What it is |
|---|---|
| **Wild** | A creature from the biome's spawn pool. The node shows its gold range and material chance (§5.1) |
| **Alpha** | +50% HP, +25% damage, double gold and a guaranteed material. Its reward gives **2 picks** |
| **Spring** | Heal the whole party to 100% (reviving KOs) |
| **Warden** | Mid-run boss (§8). The Warden and Boss nodes show only their icon and name; what they do is learned in the fight |
| **Boss** | Noctyrm (§8) |

**Enemy scaling:** wild HP = `90 × (0.6 + 0.4 × speciesHP / 55) × (1 + 0.15 × (floor − 1))`. Damage ×`(1 + 0.10 × (floor − 1))`. Biome B wilds drawn from the Biome A pool scale as if 2 floors higher.

## 7. Rewards (after every non-boss win)
The fight's loot (§5.1), Essence and pack points (§11; "+N pts · Pack earned!" when they fill the meter, with a toast pointing to the title screen) are shown in a ribbon under "Victory" (each drop pops in) and banked first. A pip row shows the picks left. Then pick **1 of 3**: **Upgrade a card**, **Heal** (40% max HP to the whole party, reviving KOs), or **Scavenge** (+1 random material). Alphas give 2 picks; repeats are allowed.

- **Upgrade:** choose any equipped card in your party, then **+30% effect** or **−1 cost** (min 0). Each card can be upgraded once. A card with no number to scale (e.g. Static, Flicker) offers only −1 cost.
- Card upgrades last for the current run only (permanent upgrades are §5.2).

## 8. Warden and Boss
- **Warden: Gravewood** (floor 4), a Thorn apex. **300 HP.** Every 3rd attack is heavy, alternating **Bramble Crush** (Thorn) and **Wildfire Roar** (Ember), so each cycle needs at least one swap read.
- **Noctyrm** (floor 8): **270 HP.** Shifts element every **7s**. Its heavy (**Eclipse Volley**, three projectiles) uses its *current* element.

## 9. No evolution
Creatures don't evolve. Each of the 12 is a unique creature with a single form and a single image. Within a run, a creature only changes through §7 card upgrades; across runs, through its loadout (§16) and its permanent upgrades (§5.2).

## 10. Roster (12 creatures)
Each creature has 3 card slots: **Strike / Skill / Signature**. They are the cards it brings to the deck and it owns them in battle: it plays them in full while it leads, and another lead of its element plays them as basic hits (§4.3). Strike has one option; Skill and Signature each have the default and two alternates, unlocked by collecting copies (§16.3): the alternate Skill at **2** copies, the alternate Signature at **3**, the third Skill at **5**, the third Signature at **7**. Each creature also has a built-in Trait (§16). HP is max HP at run start before Vitality upgrades (§5.2). Atk/Spd only affect it as an enemy.

"N dmg ×H" hits H times; each hit gets the chain bonus. "+N if Burned" (or Soaked, Rooted) adds N damage if the enemy has that status.

### Ember
| Creature | Role | HP | Strike | Skill | Alt Skill | Signature | Alt Signature | Trait |
|---|---|---|---|---|---|---|---|---|
| **Emberwick** ⭐ | Balanced | 50 | Peck (1): 6 dmg | Kindle (2): apply Burn | Flare Step (1): +1 energy, +1 chain | Wickflare (3): 14 dmg, +8 if Burned | Wildfire (3): 8 dmg, apply Burn, +1 chain | Afterglow |
| **Cinderpip** | Glass cannon | 35 | Scorch (1): 7 dmg | Flicker (1): next card costs 1 less | Flare Up (1): +1 chain, take 2 | Flashfire (4): 24 dmg | Ember Barrage (3): 5 dmg ×3 | Quickfuse |
| **Kilnback** | Tank | 75 | Bash (1): 5 dmg | Hearth Shell (2): shield 12 | Forge (2): shield 6, next Strike ×2 | Slow Burn (3): apply Burn, shield 8 | Magma Ram (3): 16 dmg, take 4 | Bulwark |

### Tide
| Creature | Role | HP | Strike | Skill | Alt Skill | Signature | Alt Signature | Trait |
|---|---|---|---|---|---|---|---|---|
| **Bellspring** ⭐ | Sustain | 55 | Splash (1): 5 dmg | Drench (2): apply Soak | Tidecall (2): shield team 5 | Lantern Tide (3): 10 dmg, heal team 8 | Undertide (3): 14 dmg, +6 if Soaked | Ebb |
| **Puddlet** | Healer | 40 | Drip (1): 4 dmg | Mend (2): heal self 15 | Bubble (1): shield 7 | Spring Rain (4): heal team 12, cleanse team | Wellspring (3): heal team 6, +2 energy | Undercurrent |
| **Brinecrab** | Tank | 80 | Pinch (1): 6 dmg | Barnacle (2): shield 14 | Brace (1): next hit taken reflects 30% | Undertow (3): 12 dmg, apply Soak | Tidal Clamp (3): 10 dmg, shield 10 | Counterweave |

### Thorn
| Creature | Role | HP | Strike | Skill | Alt Skill | Signature | Alt Signature | Trait |
|---|---|---|---|---|---|---|---|---|
| **Truffmole** ⭐ | Control | 55 | Dig (1): 6 dmg | Tangle (2): apply Root | Burrow (2): shield 8, next Strike ×2 | Sporeburst (3): 12 dmg, heal self 6 | Rootquake (4): 16 dmg, apply Root | Deep Roots |
| **Brambat** | Drain | 40 | Nip (1): 5 dmg, heal self 2 | Thornveil (2): next hit taken reflects 50% | Hemlock (2): apply Root, heal self 6 | Leech Dive (3): 12 dmg, heal self 50% of damage | Thorn Storm (4): 8 dmg ×2, next hit taken reflects 30% | Thirst |
| **Mossling** | Support | 50 | Swat (1): 5 dmg | Overgrow (2): apply Root, shield 6 | Photosynth (2): heal team 5 | Canopy (3): shield team 8 | Strangle Vine (3): 10 dmg, +6 if Rooted | Overshade |

### Volt
| Creature | Role | HP | Strike | Skill | Alt Skill | Signature | Alt Signature | Trait |
|---|---|---|---|---|---|---|---|---|
| **Skiray** | Tempo | 45 | Zap (0): 3 dmg | Static (2): apply Shock | Tailwind (1): +2 chain | Gale Strike (3): 10 dmg, +1 chain | Arc Lash (3): 6 dmg, apply Shock | Relay |
| **Sparkit** | Glass cannon | 35 | Jolt (1): 7 dmg | Overcharge (1): +2 energy, take 4 | Supercharge (2): next Strike ×3 | Thunderclap (4): 22 dmg | Ball Lightning (3): 14 dmg, +1 chain | Live Wire |
| **Coilsnail** | Tank | 70 | Prod (1): 5 dmg | Capacitor (2): shield 10, next Strike ×2 | Grounding (2): shield 8, cleanse team | Discharge (3): damage equal to your shield, consuming it | Static Field (3): shield team 6, apply Shock | Grounded |

### Third options (Skill at 5 copies, Signature at 7)
| Creature | Third Skill | Third Signature |
|---|---|---|
| **Emberwick** | Stoke (2): 6 dmg, +6 if Burned | Pyre Bloom (4): 8 dmg ×2, apply Burn |
| **Cinderpip** | Sootburst (2): apply Burn, +1 chain | Pop Flare (2): 9 dmg, +1 chain |
| **Kilnback** | Ashwall (2): shield team 5 | Furnace Heart (4): shield 12, heal self 10 |
| **Bellspring** | Tolling Wave (2): heal team 4, cleanse team | Riptide Peal (4): 8 dmg ×2, apply Soak |
| **Puddlet** | Puddle Hop (1): +1 energy, heal self 4 | Drizzle Volley (3): 4 dmg ×3, heal team 4 |
| **Brinecrab** | Saltcrust (2): apply Soak, shield 7 | Abyss Pincer (4): 16 dmg, +8 if Soaked |
| **Truffmole** | Truffle Hunt (1): +1 energy, next Strike ×2 | Fairy Ring (3): apply Root, heal team 6 |
| **Brambat** | Briar Bite (2): 4 dmg ×2, heal self 50% of damage | Gorge (3): heal self 8, next Strike ×3 |
| **Mossling** | Moss Pillow (1): shield 5, +1 chain | Verdant Bloom (4): heal team 7, shield team 5 |
| **Skiray** | Crosswind (1): 4 dmg, +1 chain | Squall Dive (4): 6 dmg ×3, +1 chain |
| **Sparkit** | Crackle (2): 3 dmg ×3, +1 chain | Short Circuit (3): 19 dmg, take 6 |
| **Coilsnail** | Coil Up (1): shield 4, +1 energy | Volt Bastion (4): shield 16, next hit taken reflects 50% |

Every third option has a number the +30% reward upgrade can scale. Roles: status setup or payoff (Stoke, Sootburst, Saltcrust, Fairy Ring, Abyss Pincer), burst (Pyre Bloom, Riptide Peal, whose second hit lands on the Soak its first applies, Squall Dive, Short Circuit), team utility (Ashwall, Tolling Wave, Verdant Bloom, Drizzle Volley), cheap chain tempo (Puddle Hop, Truffle Hunt, Moss Pillow, Crosswind, Crackle, Coil Up, Pop Flare) and a big next Strike (Gorge).

- **Shields** absorb damage until broken, and decay 20%/s once 3s have passed since they were last added to.
- **Spawn pools** (who you fight; any species can appear, owned or not, and none can be caught): Biome A (floors 1–3): Cinderpip, Puddlet, Brambat, Skiray, Kilnback, Mossling. Biome B (5–7): Brinecrab, Sparkit, Coilsnail, plus the Biome A pool at +2 floors' scaling.

## 11. Collection and packs
- **New install:** you own the 3 starters.
- **Packs are the only way to get creatures and copies.** Three sources, all the same pack:
    - **Daily pack:** one free per day, resetting at **04:00 device-local time**.
    - **Pack meter:** every fight won adds pack points: Wild **2**, Alpha **3**, Warden **5**, Noctyrm **10**. They are banked the moment the fight is won, like loot, so they're kept on a loss or a retreat (retreating a fresh run earns nothing, since points come only from wins). Every **50** points banks one **pack token**; overflow carries into the next meter. That is about one pack per 5 runs; a full winning run earns about 0.6 of a pack.
    - **Creature pack** bought in the item shop for **150** gold (§5.3).
- **Pick 1 of 3.** A pack rolls **3 different species** from all 12; a species you don't own is **3×** as likely as one you own. The three cards flip face up one after another (tapping a face-down card turns them all over, so there are no blind picks); each shows the creature's face, its name, NEW or the copy it would become ("Copy 3/10"), and what that copy gives (its role for a new creature, the card or shiny it unlocks, or gold when it's complete). Tap one to keep it; the others fade, and a line says what it gave. The roll is saved as **pending** until a pick is made, so closing the app never rerolls, and any pack source opens the pending pack first without spending anything.
- **Copies.** Keeping a creature you don't own adds it to the collection (1 copy); keeping one you own adds a copy. Copies unlock its alternate cards and, at **10**, make it **shiny** (a hue-shift with a sparkle on entry; §16.3). A copy beyond 10 converts to **25** gold. A pack is never empty. From the title, a new creature joins the team if there's room.
- **Opening packs:** the title dock's pack cell shows how many packs are waiting (a pending pick, today's free pack and the tokens: "Pack", "Packs ×3") with the meter under it ("32/50"), gold-dotted when one is ready; tapping it opens the pending pick first, then the daily pack, then a token.
- **Starting a run:** pick a team of up to 3 owned creatures on the Team screen (§4.2). Each starts at its §10 stats plus its permanent upgrades (§5.2), with its saved loadout (§16).
- **Title:** the lead creature on the stage, the logo and tagline on a scrim, a team pill (portraits, who leads, best run) that opens the Team screen, one **Start expedition** plaque, and a four-icon dock (Team, Packs with a gold dot when one is ready, Collection, Item shop) with counts.
- **End of run:** floor reached, gold earned, Perfect Swaps and time as large numbers, then a ribbon of everything banked this run (loot and Essence), the **pack meter** (it fills from where it stood at the run's start over this run's points, "+N this run" and "32/50 · 18 to go"; each time it fills it reads "Pack earned!" with a heavy haptic, and an **Open pack** button appears beside it), party portraits, **Run again**, and Item shop / Title. Loot was banked as it dropped; a win adds **+50** gold. The screen links to the item shop.
- **Collection screen:** the selected creature stands in a framed specimen window; a six-wide portrait grid (unowned are "?" silhouettes); a detail panel with **Cards / Trait / Upgrades** tabs (upgrade tracks are five-pip bars; the Cards tab opens with "Copies n/10" as pips and what the next copy unlocks, and locked cards say how many copies they need). Back and the open tab's currency sit in the header: copies for Cards, Essence for Trait, gold and materials for Upgrades. Tap any portrait to see its cards and Trait. It is also the **loadout editor** (§16) and the **upgrade screen** (§5.2) for owned creatures.
- **"Run again"** on the results screen restarts immediately with the same team.
- **Persisted** (through `Platform.store_get`/`store_set` in `core/platform.gd`, saved to `user://save.cfg`): `copies` (per species), `packDay`, `packPts`, `packTokens`, `packPending` (the rolled choices), `packSource` (`daily`/`token`/`shop`), `best`, `wins`, `lineup` (last team; `starter` is read once as a fallback), `muted`, `essence`, `learned` (learned Traits, plus card ids unlocked with Essence before copies), `loadout`, `loot` (gold and materials), `upgrades` (per-species track levels). The old `owned` and `shiny` keys are only read to migrate (§16.3).

## 12. Feel
- **Haptics:** light on card play, medium on a hit landing, heavy on a Perfect Swap or a pack reveal.
- **Hit-stop:** 60ms on heavy and super-effective hits, 120ms on a Perfect Swap.
- **Damage numbers:** coloured by element, larger for super-effective hits, "RESIST" label on resisted hits.

## 13. Art direction and asset budget
- **Direction: HD-2D**, in the spirit of Octopath Traveler. Low-resolution pixel-art sprites in a lit, painterly diorama. Depth of field, bloom, lighting and particles come from the engine, never from the sprite.
- **Cast:** monsters (the roster, Warden, boss) and **humanoid characters**. Humanoids are generated in ChatGPT with the template in `docs/HD2D.md`; monsters use the same Style Block so both read as one game.
- **Locked style constants** (full list in `docs/HD2D.md`): humanoids about 128 px tall and chibi (about 3 heads, like Octopath Traveler's field sprites, always adult characters); monsters about 100 px × species size (in-game height set by the manifest, so the pixel count can vary slightly); three-quarter view facing right; key light from the upper left; 1 px selective outline, never pure black; at most 32 colours asked for in the prompt. `scripts/hd2d-sprite.py` snaps ChatGPT's output onto its own pixel grid without merging detail.
- **Budget:** 12 creature stills, 1 Warden, 1 boss, 2 biome backgrounds = **16 images**, plus humanoids once they have a role (§15). Element icons and card frames are drawn in code; card and portrait faces are crops of the creature sprites (a `face` rect per species in `manifest.gd`), so they add no images. Shinies are a filter. 
- **Current art** (`godot/art/hd2d/`): real sprites for Brinecrab, Puddlet, Brambat and Bellspring (`painted` entries in `manifest.gd`). Every other species still uses a placeholder: one of the 3 HD-2D anchors, hue-remapped per element (`recolor.gd`; mapping in `manifest.gd`). The rest are generated a few per day with `/hd2d-batch` (Codex, `scripts/hd2d-codex.py`). The diorama is real 3D (Godot): procedural meshes and pixel textures, a warm key light from the upper left with shadows, depth of field, glow, light shafts, fog. Biome 0 is sunlit forest ruins, biome 1 moonlit castle ruins with lanterns. No background images.

## 14. Out of scope (later)
Events, rival tamers, tamer cards, eggs, Warden part-breaking, crafting beyond Trait learning and material upgrades (§5, §16), equipment items, more than two alternates per card slot, sightings-based packs, evolution (§9), a second Warden, ranked mode and leaderboards, a daily seeded run, cosmetic card frames, monetization.

## 15. Open tuning questions (decide by playing)
- Swap pace: is a 6s swap cooldown with no auto-swapping bench cards too clunky, or are hands clogged with off-element and dead cards too often? Basic hits (§4.3) keep same-element teams moving; watch whether they make mono-element lineups dominate or make swapping to the owner feel pointless. Levers: `BAL.swap_cd`, `discard_cost`, `basic_cost`, `basic_dmg`. With no post-fight revive, also watch whether runs snowball after the first KO (levers: Spring frequency, Heal reward size).
- Pack pace: with the daily pack, the pack meter (about one pack per 5 runs) and bought packs (150 gold), how fast do players own all 12, and reach 5 and 7 copies of the creatures they play? Levers: `BAL.pts_wild`/`pts_alpha`/`pts_warden`/`pts_boss`, `pack_meter`, `pack_choices`, `pack_new_weight`, `shop_pack`, `dupe_gold`, and the copy counts in `Data.COPY_TIERS`.
- Loot and upgrade pace: target about **1 permanent upgrade per run**. Levers: `BAL.wildGold`/`goldPerFloor`/`wildMatChance`/`alphaGoldMul`/`alphaMats`/`wardenGold`/`wardenMats`/`bossGold`/`winGold`, `upGold`, `upMax`, `upDmg`/`upSpirit`/`upHp`, and shop prices `shopMat`/`shopPack`/`shopSell`.
- Essence earn rate: Essence now only learns Traits, so it piles up faster than it's spent; target about **1 Trait every 2–3 runs**. Levers: `BAL.ess_wild`/`ess_alpha`/`ess_warden`/`ess_boss`, `trait_cost`.
- Do the chain Traits (Live Wire, Quickfuse, Relay) stack too strongly when socketed together? Levers: raise `BAL.livewireChain`, or allow only one chain Trait per lineup.
- Humanoid characters (§13) have art direction but no in-game role yet. Candidates: the player's tamer on the title and map screens, the Warden's keeper, rival tamers (§14). Decide before generating more than the anchor.
- Late-floor difficulty: permanent upgrades (§5.2) make veteran teams stronger, so enemy scaling may need to rise for them. Watch floor 6–8 death rates. The levers are `BAL.hpPerFloor`/`dmgPerFloor`, Spring frequency, Heal reward size and the upgrade percentages.

## 16. Loadouts, copies, Essence and Traits
Loadouts give options, not power: every alternate is a sidegrade. Raising a creature's numbers is the job of permanent upgrades (§5.2).

### 16.1 Loadouts
- Per creature: **Skill** (default or one of two alternates), **Signature** (default or one of two alternates), and a **Trait** socket. Strike has one option. Alternates are in §10; they unlock from copies (§16.3).
- Loadouts are saved per species and edited only on the **Collection screen**, never mid-run, so "Run again" stays one tap (pillar 3).
- A creature uses its saved loadout whenever it joins a run. It's fixed for that creature for the rest of the run.
- Locked or missing choices fall back to the default.
- Unlocking a card equips it (when a copy reaches its tier); learning a Trait sockets it in the creature being viewed (one tap fewer).

### 16.2 Traits
- Every creature has a built-in Trait in its socket. **The socket is never empty.**
- Once a Trait is **learned**, other creatures can socket it. A learned Trait sits in **only one** other creature at a time: socketing it elsewhere returns the previous holder to its built-in Trait. The creature it's built into always keeps it.
- A learned Trait is usable only while its source creature is owned.
- "It" / "its" means the creature holding the Trait. "Its card" means a card it owns, played in full while it leads (§4.3). Basic hits never trigger Traits.

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
| **Relay** | Skiray | After you swap to it, your next card costs 1 less |
| **Live Wire** | Sparkit | The first time its card reaches chain **3+**, +1 energy |
| **Grounded** | Coilsnail | Can't be Shocked; a Shock on it gives +1 energy instead |

### 16.3 Copies
Each species has a persisted copy count (0 = not owned). Copies come only from packs (§11), and each tier is reached once, permanently:

| Copies | Unlocks |
|---|---|
| **1** | the creature (owned) |
| **2** | its alternate Skill |
| **3** | its alternate Signature |
| **5** | its third Skill |
| **7** | its third Signature |
| **10** | shiny |

A card unlocked by a copy is equipped at once. Beyond 10, each copy converts to **25** gold. The tiers are `Data.COPY_TIERS` (`copies_for(slot, i)`, `max_copies()`).

**Old saves migrate:** an owned species with no copy count has 1 copy, a shiny one has 10, and alternate cards already unlocked with Essence (their ids in `learned`) stay unlocked.

### 16.4 Essence
One persisted currency split into the 4 elements, spent **only on Traits** (cards unlock from copies). The end-of-run screen shows the Essence earned.

| Source | Essence |
|---|---|
| Defeat a Wild | **+1** of its element |
| Defeat an Alpha | **+2** of its element |
| Defeat the Warden | **+3** Thorn and **+3** Ember |
| Defeat Noctyrm | **+2** of every element |

| Spend | Cost | Requires |
|---|---|---|
| Learn a Trait | **8** Essence of its source creature's element | the source creature is owned |

Learned Traits are permanent.

---

# Part 2: Engineering

## Session start: catching up
A SessionStart hook (`.claude/hooks/session-context.sh`, registered in `.claude/settings.json`) prints the last 10 commits and any uncommitted changes into context automatically.
1. **Recent work:** that hook output. The commit messages say what changed and why. If it's missing, run `.claude/hooks/session-context.sh` yourself.
2. **Current state:** read "Current state" and "Releasing" below for what works, what is placeholder, what has shipped and how builds work. That section is the authority for anything git can't see (TestFlight uploads, credentials, the build server).
3. **Uncommitted work:** also in the hook output.

Keep both up to date: write commit bodies that explain *why*, and edit "Releasing" in the same change whenever release state changes (a new upload, a credentials change, a pipeline change).

## What this is
A **Godot 4.7.2** game (`godot/`, GDScript, Mobile renderer), exported to iOS on the Mac build server and submitted from this machine.

It was ported from a PixiJS web app in an Expo WebView (TestFlight builds up to 0.2.0 (5)); that code was deleted after the port and lives on only in git history (the last commit with them is `d1109ef`).

`eas/` is not app code: it only links the repo to the EAS project `@taigamura/wildbound` so `eas submit` can upload ipas with the App Store Connect key stored on EAS, and it holds the downloaded signing credentials (gitignored).

`godot/CONTRACT.md` is the module contract from the port: which autoload owns what, the cross-module APIs, and the naming rule (TS names → snake_case). Keep it in sync when an API changes.

## Current state (2026-10-08)
- **Shipped:** v0.3.0 build 11 on TestFlight (build 6 was the first Godot build). Everything in Part 1 is implemented: real-time card combat with the fanned hand and the owner rule (a card fires in full only for its owner; other same-element leads play it as a basic hit), statuses, Perfect Swap, chain, 12 creatures with three options per Skill/Signature and Traits, the 8-floor run with Warden and Noctyrm, loot, permanent upgrades, item shop, the pack meter, pick-1-of-3 packs (daily, meter tokens, bought) with per-species copies that unlock cards and shininess, Essence for Traits, the Team screen (face tiles, pick a slot then a creature; not yet in a TestFlight build), Collection with the loadout editor. Build 11's pack, copies and owner-rule work hasn't been played on a device yet.
- **Art is mostly placeholder:** 4 of 14 creatures have real sprites (Brinecrab, Puddlet, Brambat, Bellspring); the 3 HD-2D anchors (Sable, ember fox, dragon) stand in for the rest, recoloured per element (§13). The anchors are painted in Ember, so the Ember placeholders (Emberwick = fox, Cinderpip = Sable, Kilnback = dragon) show unrecoloured and look finished, but they aren't: a species is done only when `godot/art/hd2d/<key>.png` exists. `/hd2d-batch` generates the remainder a few per day.
- **Unverified on device:** frame rate on a real iPhone (the 3D stage was only measured on a software renderer; first lever if it drops below 60 fps: render the 3D scene at ~0.75 resolution), the UI shaders added in build 10 (card foil sheen, energy crystal, face dimming), Pixelify Sans crispness at device scale, haptics, safe-area insets.
- **UI redesign shipped in build 10:** warm HD-2D palette, Pixelify Sans + Atkinson Hyperlegible, window frames, brass plaque, Crystal Foil cards with teammate faces, the battle HUD diet with the energy crystal, title dock, bestiary, map trail, reward and results screens. Follow-ups are in `docs/UI-QUEUE.md`.
- **Known gaps from the port:** no background blur on panels; a card that turns dead repaints in place instead of flying off.
- **Balance is untuned** for the loot economy and 3-creature teams from floor 1 (§15).
- **Saves:** the Godot app's save file (`user://save.cfg`) starts fresh; progress from the web builds (≤ 0.2.0) does not carry over.
- **Device floor:** iPhone XS or newer (A12), required by Godot's Mobile renderer.

## Commands
Run from the repo root. On this machine always pass `--audio-driver Dummy` (Godot hangs at startup without it here). **Never open Godot windows on the desktop:** any non-headless run (`--shot`, `stage_preview.gd`) goes through `scripts/godot-bg.sh` instead of `godot`, which renders on a private Xvfb display (same pixels; `GODOT_WINDOW=1` shows the window when you really want it). `scripts/ui-check.sh` already does this.
- `godot --headless --audio-driver Dummy --path godot --quit`: load check (parse errors show here)
- `godot --headless --audio-driver Dummy --path godot --script res://tests/test_core.gd`: core logic tests (all must pass)
- `scripts/godot-bg.sh --audio-driver Dummy --path godot --resolution 390x844 -- --shot=<screen> --shot-dir=DIR`: render one screen to `DIR/wb-<screen>.png` and quit (`--shot-scroll=PX` scrolls a sheet). Screens: `title team team-swap map map-sel map-warden map-late reward reward-warden upgrade party end end-win pack pack-pick coll coll-trait coll-up shop battle battle-shared battle-heavy inspect flick` (`ALL` in `scripts/ui-check.sh` is the checked list). `--shot=team-swap` shows the Team screen with every creature owned, a full team and the cursor on slot 2 (it uses a scratch save, `user://shot-team-swap.cfg`, never `save.cfg`). `--shot=pack` shows a daily pack's three choices (a new creature, a copy that unlocks a card, a copy that turns shiny) and `pack-pick` the same pack after keeping Bellspring; both use the scratch save `user://shot-pack.cfg`. `--shot=battle-shared` shows every card state at once (a basic hit, a dead card, an upgraded card, an unaffordable one; scratch save `user://shot-battle-shared.cfg`). Renders for real here (Vulkan llvmpipe).
- `scripts/ui-check.sh [screen...]`: the screenshot UI check. Renders every `--shot` screen at 390×844 (simulated 47/34 px notch insets) and 375×667 (20/0) in deterministic mode, lints the layout (`godot/tests/ui_check.gd`: offscreen or outside the safe area, a box spilling out of its parent, squashed boxes, wrapped text overflowing, ellipsis truncation, a corner badge covering text, creature art under a panel, low-contrast text over the scene, header/sheet overlap) and diffs against the goldens in `godot/tests/golden/<size>/`. Shots, `.fail.png` (findings outlined) and `.diff.png` land in `/tmp/claude-1000/ui-check/`. `--update` accepts the current renders as goldens; only do that after looking at them. `NO_GOLDEN=1` runs the layout rules only (for parallel branches that will all change the look; update the goldens once after merging). `UI_CHECK_OUT` and `UI_CHECK_JOBS` (default 3) set the output folder and parallel runs. A full run (23 screens × 2 sizes) takes about 4 minutes.
- `scripts/godot-bg.sh --audio-driver Dummy --path godot --script res://tests/stage_preview.gd`: stage-only visual test (both biomes, effects); `-- --pair=<enemy>,<partner>` puts two species on the biome 0 pedestals instead (checks a new sprite)
- `godot --path godot -e`: the editor

## Where things live (all under `godot/`)
- Balance and content: `core/data.gd` (`Data`). `BAL` holds every tuning number; `SPECIES` the roster and cards (each slot a list: `[default, ...alternates]`); `TRAITS` the Trait definitions; `COPY_TIERS` the copy counts that unlock card options and shininess (`copies_for(slot, i)`, `max_copies()`).
- Combat, statuses, Perfect Swap, chain, basic hits, Trait effects: `game/battle.gd` (`Battle`). It emits `card_played(i)` / `card_denied(i, why)`; it never touches card Controls.
- Run state and card resolution (the owner rule: `card_basic`, `card_waiting_for`, `card_block`): `game/state.gd` (`S`), entity classes `game/mon.gd`, `enemy.gd`, `card_ref.gd`, `map_node.gd`.
- Collection (copies and their migration), packs (daily, tokens, pending pick), the pack meter, loot wallet, permanent upgrades, shop trades, Essence and Traits, card unlocks from copies, loadouts, the last lineup: `game/meta.gd` (`Meta`).
- Persistence and haptics: `core/platform.gd` (`Platform`, `user://save.cfg`). Sound: `core/audio.gd` (`Sfx`, synthesized at startup).
- Map, nodes, loot and pack-point drops, rewards, card upgrades, lineup, end of run with the pack meter animation, title, team builder (`scr-team`: slot cursor, face tiles), quit (`quit_tap`/`quit_run`), the pick-1-of-3 pack screen, item shop, Collection with loadout editor and upgrades: `game/run.gd` (`Run`).
- HUD and the card fan: `ui/ui.gd` (`Ui`, plus the energy `ui/crystal.gd`); screen frames `ui/screens.gd`; shared look (palette, fonts, Theme, builders) `ui/kit.gd` with the window frame `ui/win_style.gd` and hairline lists `ui/rows.gd`; card face `ui/card_view.gd` (+ `card_foil`/`card_face` shaders); map trail `ui/map_trail.gd`; popups, banners, toasts, the loot reveal `ui/fx.gd` (`Fx`). Fonts in `ui/fonts/` (OFL licences beside them). Frame loop and `--shot`: `scenes/main.gd`.
- HD-2D stage: `render/stage.gd` (`Stage`: 3D world, camera, lights, WorldEnvironment, pedestals, shield, `projectile`, `lightning`), `render/actor.gd` (`Actor`), `render/particles.gd`, `render/feel.gd` (hit-stop, slow-mo, shake), `render/layout.gd` (screen band, `U`, spots). Art: `art/hd2d/` (`manifest.gd` species→sprite, `recolor.gd` per-element recolour, `diorama.gd` the two biomes, `tex.gd` procedural pixel textures, `pedestal.gd`, `shaders/`).
- HD-2D sprite template: `docs/HD2D.md`; per-creature prompts `docs/hd2d/prompts.md` (+ `.json`, generated by `scripts/hd2d-prompts.py`); Codex generation `scripts/hd2d-codex.py` (driven by the `/hd2d-batch` skill); ChatGPT/Codex originals `docs/hd2d/original/` (gitignored, local only); anchors in `docs/hd2d/anchors/`; normalizer `scripts/hd2d-sprite.py`.
- iOS: `godot/export_presets.cfg` (`iOS` preset), `godot/ios/` (icon, launch images, `build-number.txt`, `mac-build.sh`), `scripts/ship-ios-godot.sh`.

## Rules
- **Coordinates:** modules pass **screen px** on the 390×844 base canvas (stretch `canvas_items`/`expand`). Only the stage converts to 3D (`Actor.place(x, y, face)` puts the feet at that screen point; `head()` returns screen px). `Layout.U` is the world unit in px; actor `off` is in U.
- **Gameplay stays art-agnostic:** game code talks to `Actor`, `Stage`, `Particles`, `Feel`, `Fx` and `Ui` APIs only, never to stage nodes or materials.
- **Species keys** are the lowercase creature names (`emberwick`, `kilnback`, `warden`, `noctyrm`). The HD-2D manifest keys sprites by them.
- **Stale callbacks:** `S.tok` is bumped when a battle or run ends. Every delayed callback (tween callbacks, `create_timer`) captures `tok` and bails if it changed.
- **Timing:** game-time effects use tweens/timers in scaled time so they obey hit-stop and slow-mo (`Feel` drives `Engine.time_scale` from real time). UI motion (the card fan, screens) runs in real time.
- **Input:** the hand uses touch/mouse press-drag-release. Press magnifies instantly; horizontal movement scrubs the magnification between cards (hysteresis `SCRUB_HYST`); upward travel past `LIFT_LOCK` commits a swipe on that card; release plays it if the `FLICK_*` thresholds are met, otherwise the card returns to the fan. Constants are in `ui/ui.gd`.
- **Storage and native calls** only in `core/platform.gd`. So is the clock: use `Platform.ticks_usec()`/`ticks_msec()`, never `Time.get_ticks_*`, or the UI check's screenshots stop being deterministic.
- **UI layout:** nothing hangs off its box (badges and tags sit inside the card or chip), text never runs under a corner piece, and creature art never sits under a header or sheet. `scripts/ui-check.sh` enforces this; a deliberate exception sets `ui_check_skip` (or `ui_check_free` for a freely placed node like a lifted hand card) with a comment saying why.
- **Reserved word:** `trait` is reserved in GDScript; the field is `Mon.trait_key`, and dictionary keys `"trait"` are read with brackets.
- **Assets:** pixel art uses nearest filtering; the only image files are the HD-2D sprites in `godot/art/hd2d/` (everything else is procedural). Keep it that way unless a real asset is approved.

## Releasing (iOS / TestFlight)
- **Identity:** bundle ID `com.taiga.wildbound`, App Store Connect app ID `6818680785`, Apple team `6R43H3SA48`. Version: `application/short_version` in `godot/export_presets.cfg` (0.3.0). Build number: `godot/ios/build-number.txt` holds the last build uploaded to App Store Connect; the script builds with +1 and writes it back only after a confirmed submit. Commit it with the History entry.
- **Normal path: `scripts/ship-ios-godot.sh`** (also what `/ship-ios` runs, via `.claude/ship.json`), from this box after the change is merged to `main`. It pulls `origin/main` on the Mac build server (`taigamura-MBP`, 192.168.50.175, repo `~/dev/wildbound`), copies the signing credentials to a temp dir there, imports them into a throwaway keychain (never the login keychain, so no GUI unlock is needed), has Godot 4.7.2 (`/usr/local/bin/godot` → `~/Applications/Godot-4.7.2.app`, templates in `~/Library/Application Support/Godot/export_templates/4.7.2.stable`) write the Xcode project from the `iOS` preset, runs `xcodebuild archive` + `-exportArchive` itself (`godot/ios/mac-build.sh`), copies the ipa to `dist/ios/`, and runs `eas submit`. Mac log: `~/wildbound-godot-build.log`; staged project and import cache: `~/wildbound-build/godot`. Flags: `--no-submit`, `--unsigned` (no credentials; proves Godot + Xcode compile), `--sync-local` (build the uncommitted `godot/` tree; test only), `--build-number N`.
- **Signing credentials** stay on EAS (distribution certificate, App Store provisioning profile, ASC API key). The build needs a local copy: in a real terminal (it's interactive, so not via Claude Code's `!`), `cd eas && npx eas-cli@24.10.0 credentials -p ios` → production → credentials.json → Download. That writes `eas/credentials.json` and `eas/credentials/ios/` (gitignored, never commit). Re-download when the certificate or profile is renewed. Submission uses `eas submit` with the ASC key stored on EAS; if it returns `401 NOT_AUTHORIZED`, replace the key via `eas credentials -p ios`.
- **Godot iOS requirements:** `project.godot` must set `rendering/textures/vram_compression/import_etc2_astc=true` (iOS export refuses otherwise). The Mobile renderer makes Godot require an A12 chip or newer (iPhone XS+); Apple restricts adding device requirements once an app is live, so settle this before the first App Store release.
- **History** (newest first; `/ship-ios` adds a line per upload via `releaseLog` in `.claude/ship.json`; add one by hand for any other upload):
  - 2026-10-08: v0.3.0 build 11 (local Mac build via `scripts/ship-ios-godot.sh`, commit `65a622c`, submission `8a1655c9`) uploaded to TestFlight. Pack meter (points per fight won, a pack per 50), pick-1-of-3 packs, duplicate copies unlocking cards (24 new third options) and shinies, Essence for Traits only, owner-only card effects with basic hits.
  - 2026-10-08: v0.3.0 build 10 (local Mac build via `scripts/ship-ios-godot.sh`, commit `66334ba`, submission `6c045638`) uploaded to TestFlight. UI redesign: warm HD-2D look, Crystal Foil cards with teammate faces, battle HUD with energy crystal, title dock, bestiary, map trail, reward and results screens; screenshot UI check.
  - 2026-10-08: v0.3.0 build 9 (local Mac build via `scripts/ship-ios-godot.sh`, commit `858b981`, submission `2d16d94f`) uploaded to TestFlight. First real HD-2D creature sprites (Brinecrab, Puddlet, Brambat, Bellspring); the rest are still placeholders.
  - 2026-10-04: v0.3.0 build 8 (local Mac build via `scripts/ship-ios-godot.sh`, commit `47ec1a7`, submission `a14ad88b`) uploaded to TestFlight. Cards belong to elements (any lead of the card's element plays it), readable Team screen selection with explicit replace, deck element mix.
  - 2026-10-04: v0.3.0 build 7 (local Mac build via `scripts/ship-ios-godot.sh`, commit `08935e3`, submission `feb5fc86`) uploaded to TestFlight. Lead-only cards with 6s portrait swaps, dead cards stay, no post-win revive, Team screen, scrub-and-swipe hand, in-run quit.
  - 2026-10-04: v0.3.0 build 6 (Godot port, local Mac build via `scripts/ship-ios-godot.sh`, commit `6465123`, submission `7e14b8f4`) uploaded to TestFlight. First Godot build: real 3D HD-2D diorama; same rules and screens as 0.2.0 (5).
  - 2026-10-04: v0.2.0 build 5 (EAS cloud build `e578f5af`, commit `b723ad9`, submission `4edf2407`) uploaded to TestFlight. HD-2D art style, loot/shop economy replacing capture, fanned card hand. Built in the cloud because the local Mac build is still blocked (see above).
  - 2026-10-03: v0.2.0 build 4 (EAS cloud build `bbc5de69`, commit `ccfaec7`, submission `b282dadf`) uploaded to TestFlight. Loadouts, Traits and Essence (§16). The first `/ship-ios` run: commit, PR #2 and merge worked; the local Mac build failed (see above), so it fell back to the cloud.
  - 2026-10-03: `/ship-ios` configured.
  - 2026-10-03: v0.2.0 build 2 (EAS cloud build) uploaded to TestFlight. This is the MVP design build.

## Verifying changes
- Load check and `tests/test_core.gd` (see Commands): zero script errors, all tests pass.
- UI changes: `scripts/ui-check.sh` must pass. When a golden diff is an intended change, look at the new shots, then rerun with `--update` and commit the goldens with the change.
- For stage or art changes, also run `tests/stage_preview.gd` and check both biomes.
- Debug helpers: `Battle.debug` (`hurt`, `energy`, `add`, `essence`, `loot`, `trait`, `heavy`, `copies` (raise a species' copy count), `packpts` (add pack points)).
- Before a release, `scripts/ship-ios-godot.sh --no-submit` proves the signed iOS build.
