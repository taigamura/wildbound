# Godot port: module contract

Wildbound is being ported from the PixiJS web app (`../game/src`, TypeScript) to Godot 4.7 (GDScript, Mobile renderer, iOS target). The TypeScript code is the **reference implementation**: port behaviour, numbers and text faithfully. `../CLAUDE.md` Part 1 is the design spec.

Several agents port different modules **at the same time**. This file is what keeps their code compatible. Follow it exactly; if you must deviate, write the deviation in the "Deviations" section at the bottom.

## Naming rule (the core of the contract)

Every TS module becomes one GDScript file and an autoload (singleton) of the name below. Inside it, **every exported TS identifier keeps its name, converted to snake_case**: functions, constants, object fields, dictionary keys, options-object keys.

- `playCard(i)` → `Battle.play_card(i)`; `S.swapCd` → `S.swap_cd`; `BAL.energyMax` → `Data.BAL.energy_max`; `c.maxHp` → `c.max_hp`; `emit(x, y, { n, color, spd, life, size, grav, drag, swirl, tex, streak, size1, r, up, spin })` → `Particles.emit(x, y, { "n": .., "color": .., ... })`.
- Data **values** stay as in TS: element keys `"ember" "tide" "thorn" "volt"`, species keys `"emberwick"`, slots `"strike" "skill" "sig"`, statuses `"burn"...`, node types, CSS-ish colour names become `Color`s.
- Colours: TS hex numbers (`0xff6a3d`) become `Color` (`Color.hex(0xff6a3dff)` or `Color("#ff6a3d")`). `ELEM[el].hex` → `Data.ELEM[el].hex` is a `Color`; `.glow` is an `Array[Color]`; `.css` is dropped, use `.hex`.
- TS object literals used as records (BAL, ELEM, SPECIES, TRAITS, card defs, loot, essence) become **Dictionaries** with snake_case string keys. GDScript allows `dict.key` access, so `Data.BAL.energy_max` works.
- TS interfaces for live entities become classes with `class_name` in their own file (owned by the core agent): `Mon` (`game/mon.gd`), `Enemy` (`game/enemy.gd`), `CardRef` (`game/card_ref.gd`), `MapNode` (`game/map_node.gd`), all `extends RefCounted`, with fields named per the rule. `Actor` (`render/actor.gd`, owned by the stage agent) `extends Node3D`.
- gsap tweens → `create_tween()` (Godot tweens obey `Engine.time_scale`, which is how hit-stop and slow-mo work, see Feel). `gsap.delayedCall(t, f)` → `get_tree().create_timer(t).timeout.connect(f)` (scaled time). **Stale-callback rule stays:** capture `var tok = S.tok` and bail in the callback if `tok != S.tok`.
- `Math.random()` → `randf()`; `rand(a,b)` → `Util.rand(a,b)`; `pick`, `shuffle`, `clamp` in Util.

## Coordinates

Base viewport **390×844**, `stretch canvas_items / expand` (wider or taller phones get extra canvas space). All positions passed between modules are **screen-space pixels on the canvas (Vector2 / x,y floats)**, exactly like the TS code's px. `Layout.U` is the world unit in px, as in `render/layout.ts`. The stage agent converts screen px ↔ its 3D world internally. Actor offsets (`off`) stay in **world units** (multiples of U), like TS.

## Autoloads, files and owners

Autoload order is fixed in `project.godot`. Owners may add private helpers and extra files under their own folders.

| Autoload | File | TS source | Owner |
|---|---|---|---|
| `Data` | core/data.gd | core/data.ts | core |
| `Util` | core/util.gd | core/util.ts | core |
| `Platform` | core/platform.gd | core/platform.ts | core |
| `Sfx` | core/audio.gd | core/audio.ts | core |
| `S` | game/state.gd (+ mon.gd, enemy.gd, card_ref.gd, map_node.gd) | game/state.ts | core |
| `Meta` | game/meta.gd | game/meta.ts | core |
| `Battle` | game/battle.gd | game/battle.ts | core |
| `Layout` | render/layout.gd | render/layout.ts | stage |
| `Feel` | render/feel.gd | render/fx.ts (feel, shake, hitStop, slowMo, applyShake) | stage |
| `Particles` | render/particles.gd | render/particles.ts | stage |
| `Stage` | render/stage.gd (+ actor.gd, art/hd2d/*) | render/stage.ts, render/actor.ts, render/app.ts, art/packs/hd2d/*, art/sprite/recolor.ts | stage |
| `Fx` | ui/fx.gd | render/fx.ts (popNum, banner, flash, vignette, toast, callout) | ui |
| `Ui` | ui/ui.gd (+ ui/*.tscn, theme) | game/ui.ts, index.html, style.css | ui |
| `Run` | game/run.gd | game/run.ts | ui |
| (main scene) | scenes/main.gd, main.tscn | main.ts | ui |

Not ported: the Sticker and Dusk art styles, the art picker, `?art=`, the pack exporter (`tools/`). HD-2D is the only look.

## Cross-module APIs (the parts others call)

Signatures are the TS ones under the naming rule. The extra or changed ones:

**Platform** (core): `store_get(key: String, default)`, `store_set(key: String, value)` — persisted in `user://save.cfg` via ConfigFile (keys as in CLAUDE.md §11 plus `lineup`, `loot`, `upgrades`). `haptic(kind: String)` — `"light" "medium" "heavy" "success" "warning"`; on iOS use `Input.vibrate_handheld(ms)` (durations ~10/20/35 ms), elsewhere no-op.

**Sfx** (core): one method per TS `SFX` entry (`Sfx.hit()`, `Sfx.crit()`, `Sfx.deny()`, `Sfx.zap()`, `Sfx.caught()` …), synthesized like TS (AudioStreamGenerator or pre-baked AudioStreamWAV tones). `is_muted()`, `set_muted(v)`, `audio()` (unlock; no-op is fine).

**S** (core): every field of TS `S` (`mode, party, lineup, active, draw, disc, hand, energy, floor, enemy, swap_cd, auto_t, chain, chain_t, discount, wired, tok, picks, stats, nodes, actors, em, title_actor, uid`) and helpers `act() mon(uid) team() new_mon(key, shiny=false) card_el(r) card_by(r) card_of(r, by) card_cost(r) card_block(r) card_dead(r) card_benched(r) healthiest() is_heavy(e) heavy_of(e) in_perfect_window(e) actor_for(c) active_actor() drop_actor(uid) clear_actors()`. `card_of(r, by = null)` returns a Dictionary `{def, pow, src, by, el}`: cards belong to an element (`card_el(r)` = the source creature's element); `by` is the creature that fires it (default `card_by(r)`: the lead when it shares the element, else the source), whose Power/Spirit apply; the source's `ups[slot]` carries in-run upgrades. `card_dead(r)` = no living lineup member of the card's element; `card_benched(r)` = not dead and the lead isn't of its element (`card_block` → `"bench"`). `actor_for(c)` creates `Actor.create(c.key, c.el)` on demand (see Stage).

**Battle** (core): `start_battle(n: MapNode)`, `play_card(i: int) -> void`, `swap_tap(uid: int)`, `tick_battle(dt, t)`, `debug` (Dictionary of Callables, same entries as TS). Battle calls `Ui.*`, `Fx.*`, `Feel.*`, `Particles.*`, `Stage.*` and `Run.place_player / after_fight / end_run` exactly as TS does. **TS `projectile()` and `lightning()` move to Stage** (below); `lunge()` stays in Battle (it tweens `actor.off`).
Play-success signal for the card UI: `play_card` adds the TS `'play'` class in TS; in Godot, `Battle.play_card(i)` returns nothing but emits `Battle.card_played(i: int)` on success and `Battle.card_denied(i: int, why: String)` on refusal (`why` = `cardBlock` reason or `"busy"`). The UI animates from these signals; Battle must not touch card Controls directly. Battle calls `Ui.paint_card(i)`, `Ui.refresh_hand()`, `Ui.render_bench()`, `Ui.render_player_plate()`, `Ui.render_enemy_plate()`, `Ui.show(screen_or_null)` where TS called the ui.ts equivalents (TS `paintCard(slots[i], S.hand[i])` → `Ui.paint_card(i)`).

**Meta** (core): every export of meta.ts under the rule (`owned() is_owned addowned... wallet() add_loot buy_mat sell_mat buy_pack pack_ready open_pack upgrades(k) upgrade_cost(k, m) buy_upgrade(k, m) loadout(k) set_move set_trait ...`). Return Dictionaries where TS returned objects.

**Layout** (stage): `U: float`, `size: Vector2`, `measure_band(top_px: float, bottom_px: float, snap := false)` (the UI calls this whenever the HUD band changes; TS measured DOM `[data-band-*]` itself), `ease_layout(dt)`, `epos() ppos() tpos() -> Vector2`, `horizon() -> float`.

**Feel** (stage): `trauma`, `shake(v)`, `hit_stop(t)`, `slow_mo(t, scale)`, `reduced: bool`. Implements hit-stop/slow-mo through `Engine.time_scale` driven by real time (`Platform.ticks_usec`), and camera shake.

**Particles** (stage): `emit(x, y, opts: Dictionary)`, `ring(x, y, color, scale := 2.0, dur := 0.5, flat := true)`, `light_flash(color, pos: Vector2, v := 4.0)`, `burst(pos: Vector2, el, power := 1.0)`, `ambient(dt, fireflies, leaves)`. Screen-space positions; the stage renders them in 3D (or on a 2D layer over the 3D view — stage's choice) so they read as part of the diorama.

**Stage** (stage): `set_biome(b: int)`, `build_stage()`, `tint_arena(c: Color)`, `arena_tint() -> Color`, `update_scene(t, dt)`, `update_shield(a: Actor, shield: float, active: bool, t: float)`, `shield_pulse` (object with tweenable `s: float`, e.g. a small Resource/Object), and the two ex-battle helpers:
- `projectile(from: Vector2, to: Callable /* -> Vector2 */, el /* String or null */, o: Dictionary /* {size, arc, dur} */, on_hit: Callable)`
- `lightning(a: Vector2, b: Vector2, el: String)` (plays `Sfx.zap()` and `Particles.light_flash` like TS).
Stage owns the 3D world, camera, lights, WorldEnvironment (glow, DOF), the diorama per biome and the pedestals. It adds its world under itself (autoload node) so it renders behind the UI CanvasLayer.

**Actor** (stage), `class_name Actor extends Node3D`: `static func create(key: String, el := "") -> Actor` (adds itself to the stage). Fields: `key, el, off: Vector2` (world units, tweenable), `squash: Vector2` (= TS `sq.scale`, default `Vector2.ONE`, tweenable), `rot: float` (= TS `flip.rotation`, tweenable), `extra: float` (= TS `extra`), `face: int`, `visible` (Node3D's). Methods: `place(x, y, face)` (screen px feet position, called every frame by the main loop like TS), `head() -> Vector2` (screen px), `set_element(el)`, `set_shiny(v)`, `set_silhouette(v)`, `hit_flash()`, `update(dt)`, `destroy()`. `S.em`'s "draw behind the partner" is the stage's job (depth).

**Fx** (ui): `pop_num(pos: Vector2, text, cls := "", label := "", color := Color(0,0,0,0))`, `banner(text, sub := "", color := ...)`, `flash(op := 0.5, color := Color.WHITE)`, `vignette()`, `toast(t)`, `callout(text, color := ...)`. `cls` values as in TS (`"shield" "heal" "crit" "resist"` …). Drawn on a CanvasLayer above the 3D view.

**Ui** (ui): `slots` (the 4 card Controls), `init_hud(handlers: Dictionary {play: Callable, swap: Callable})`, `show(id_or_null)` (screen ids keep the TS names without `#`: `"scr-title" "scr-map" "scr-reward" "scr-upgrade" "scr-party" "scr-end" "scr-pack" "scr-coll" "scr-shop"`; `null` = battle HUD), `paint_card(i)`, `refresh_hand()`, `render_player_plate()`, `render_enemy_plate()`, `render_bench()`, `sync_hud()`, `card_face(...)`, `mon_chip`, `party_html` → equivalents returning Controls. Calls `Layout.measure_band` when its top/bottom HUD pieces move or a screen changes. The hand is the fan with tap-to-inspect and flick-to-play (CLAUDE.md §4.1/§4.3; port `game/ui.ts` behaviour and constants).

**Run** (ui): every export of run.ts (`start_run, place_player, show_map, after_fight, show_party, end_run, to_title, init_run_ui`) and its screens.

**Main loop** (ui, `scenes/main.gd`): port `main.ts` `frame()`: `Layout.ease_layout`, `Battle.tick_battle` when in battle, actor placement/updates (`S.em`, active actor, title actor), `Stage.update_scene`, `Stage.update_shield`, `Particles` update, `Ui.sync_hud`. Debug: expose `S`, `Battle.debug` for tests.

## Look and feel targets

- HD-2D (CLAUDE.md §13): pixel-art sprites (nearest filtering) standing in a real 3D diorama with depth of field, bloom (glow), warm key light from the upper left, light shafts, particles. Mobile renderer features only (no volumetric fog, no SDFGI).
- UI: dark rounded panels, the existing palette (see `../game/src/style.css` `:root` variables) and fonts (`../game/node_modules/@fontsource/baloo-2`, `lilita-one` woff2 files can be copied into `godot/ui/fonts/`).
- 60 fps on an iPhone 12-class device.

## Testing

- Parse/load check: `godot --headless --path godot --quit` (no errors).
- Logic tests: `godot --headless --path godot --script res://tests/<name>.gd` (a `SceneTree` script); core owns `tests/test_core.gd`.
- Screenshots: `godot --path godot --resolution 390x844` renders on this machine (Vulkan llvmpipe). Save with `get_viewport().get_texture().get_image().save_png(...)`; view the PNG with the Read tool.

## Deviations

(Owners: list any change to the APIs above here, with a one-line reason.)

**Core (Data, Util, Platform, Sfx, S, Meta, Battle):**
- `trait` is a reserved word in GDScript 4.7. `Mon.trait` is **`Mon.trait_key`**. Dictionary keys stay `"trait"` (`Data.SPECIES[k]["trait"]`, `Meta.loadout(k)["trait"]`, `Battle.debug["trait"]`), but must be read with brackets, not `.trait`.
- Card defs are Dictionaries; optional fields are simply absent (`def.get("dmg", 0)`). Keys: `name cost dmg hits bonus_if{status,dmg} from_shield status shield shield_team heal heal_team lifesteal energy self_dmg discount chain reflect next_strike cleanse`. `Data.num(v)` formats numbers like JS (2.0 → "2").
- `Data.svg(k, fill := Color.WHITE)` returns a full `<svg>` document (for `Image.load_svg_from_string`); `Data.el_css(el)` / `el_hex_css(el)` return `Color` (`Data.NEUTRAL` when no element). `Data.NO_LOOT()` and `Meta.EMPTY_ESSENCE()` are functions (aliases `no_loot()`, `empty_essence()`).
- Meta returns Dictionaries (`wallet()`, `essence()`, `boosts()`, `loadout()`, pack results `{key, shiny}`) or `null` where TS returned null (`open_pack`, `buy_pack`, `upgrade_cost`, `trait_holder`).
- `S` extras: `bench()`, `base_card(c, slot)`, `make_actor(key, el)` (all Actor creation goes through it) and `actor_factory: Callable` (tests install stub actors). `Mon.hp` is a float.
- **Actor (stage), requested:** each battle frame Battle calls `S.em.set_aura(color: Color, alpha: float)` if the Actor has that method (TS `m.aura.tint/alpha`: the wind-up glow that pulses in the last 25% of an enemy's wind-up, heavy colour during heavies). Without it the glow is skipped.
- `Battle.card_denied(i, "busy")` fires when a card is played outside `mode == "battle"` (TS returned silently; no SFX). When the last creature of an element faints, that element's cards stay in the hand and deck as dead cards; playing one discards it and emits `Battle.card_discarded(i)` instead of `card_played(i)`.
- `Platform.use_save_path(path)` points the store at another file (tests). `haptic()` also accepts TS's `"select"` and `"error"`.
- `Platform.ticks_usec()` / `ticks_msec()` are the game's only clock (never call `Time.get_ticks_*` elsewhere). In UI check mode (`-- --ui-check`, `Platform.ui_check`) they advance exactly 1/60 s per frame, the RNG is seeded and the save is a blank scratch file, so screenshots are deterministic. `Platform.safe_insets` (`-- --safe=<top>,<bottom>`) overrides `Ui.safe()`'s insets.
- `Sfx.stream(name) -> AudioStreamWAV` and `Sfx.NAMES` expose the pre-rendered sounds (rendered on a worker thread at startup).
- `tests/test_core.gd` swaps `tests/core_stubs/module_stub.gd` onto Layout/Feel/Particles/Stage/Fx/Ui/Run at runtime, so it needs every autoload to parse, but not to work.

**UI (Fx, Ui, Run, main):**
- `Ui.paint_card(i)` is TS drawInto's repaint as a whole: it ends the slot's fly-off (`.play`), repaints `S.hand[i]` and deals it in. `Ui.show(null)` (battle start) resets the hand slots and deals the opening hand itself (TS did that in `startBattle`); `Ui.deal(i, delay)` exists if Battle ever needs it. `card_denied(i, "busy")` plays no shake.
- `Ui.el` is a Dictionary of the static screen elements keyed by their index.html ids (`Ui.el.startBtn`, `Ui.el.mapEyebrow`...); `Ui.screens[id]`, `Ui.current` (shown id or null). `Ui.measure(snap := false)` re-measures the band next frame (TS `measureBand` after rAF); called by `show()`, on resize (snap) and by Run where TS called `measureBand(true)`.
- `Ui.card_face(def, el, o, variant := "mini") -> CardView` (`o`: `cost chip bench dead strong upgraded pow`; `chip` shows the element orb), `Ui.mon_chip(c, extra) -> Control`, `Ui.party_html(list = null) -> Array[Control]`.
- Look helpers live in `ui/kit.gd` (`UiKit`: warm palette, type scale, fonts, Theme, builders), `ui/rr.gdshader` + `ui/rrect.gd` (`RRect`: CSS-like rounded gradient boxes), `ui/glyphs.gd` (`Glyphs.tex(key)`: the data.ts SVG icons rasterised at runtime), `ui/screens.gd` (screen frames, plaque/quiet buttons, title tiles, logo, pack flip), `ui/win_style.gd` (`WinStyle`), `ui/rows.gd` (`Rows`), `ui/card_view.gd`, `ui/hand_slot.gd`, `ui/bar.gd`, `ui/tap.gd`, `ui/box.gd`, `ui/cap_scroll.gd`. Fonts in `ui/fonts/`.
- The UI look (docs/UI-QUEUE.md items 1-3); build new UI from these, not from raw colours and StyleBoxFlats:
  - Tokens: `UiKit.INK` (parchment text), `INK2` (secondary), `MUTE`, `NAVY`/`NAVY2` (glass, deep), `BRASS` (trim), `GOLD_HI` (selection, labels, currency), `GOLD_LO`, `PLAQUE_INK`, `HAIR` (list hairline), `LINE` (brass outline), `SEL_BG` (selected-row fill), `SCRIM`, `EL[el]` / `el_css(el)` (element accents only: rings, chips, ribbons). Old names (`DEEP`, `DEEP2`, `PANEL`, `GOLD`, `NEUTRAL`, `NIGHT`) still work, retargeted.
  - Type: `font("display")` = Pixelify Sans Bold (titles, names, numbers); `"500"` / `"700"` (`"800"` = 700) = Atkinson Hyperlegible. Sizes `T_S`/`T_M`/`T_L` = 12/14/16 body, `D_S`/`D_M`/`D_L` = 22/33/44 display (multiples of 11 keep the pixel face's grid whole), `NAME` = 16 (names in rows). Body text under 12px keeps Baloo 2 (cards and HUD micro-labels until they're redesigned). No tracked uppercase.
  - Labels: `eyebrow(t)` (the gold 12px sentence-case `.lbl`), `disp(t, size, color, o)`, `h2`, `sub`, `note`, `best`, `lbl`, `rich`.
  - Frames: `window(pad := 16, studs := true) -> WinStyle` (StyleBox: double brass border, navy glass, top-edge studs, all inside the rect) and `win(pad, studs) -> PanelContainer`; `inset(pad, gold := false)` (a quiet well inside a window); `scrim()` (header fade).
  - Lists: `rows() -> Rows` (VBox that draws hairlines between rows, skipping selected ones), `row_style(sel := false, pad)` (flat row / gold-outlined selected row), `act_style(pad)` (the act-now glow; glow is only for selected and act-now), `list_row(lead, title, sub, trail, title_c) -> HBox` (portrait, name, sub line, trailing piece).
  - Pieces: `por(c, sz, glyph, sel := false)` (element portrait orb, gold ring when selected), `chip(glyph, c, text)` (`ess`, `elchip` are chips), `tag(text, c)`, `meter(frac, c, h := 8)` (thin bar).
  - Buttons (`UiScreens`): `big(text, alt := false)` / `set_big(t, text, small)` = the brass plaque, one per screen; `quiet(text)` (`ghost` is an alias) = secondary; `meta_btn()` / `set_meta_btn(t, title, sub, ready)` = title tiles (no longer used by the title); `dock_cell(glyph)` / `set_dock_cell(t, label, sub, ready := false, dim := false)` = a title dock cell (24px icon, label, sub line; `ready` = gold with a glowing gold dot, `dim` = muted icon).
  - Bestiary and dock pieces (`UiKit`, ideas 8-9): `window_frame(studs := true)` (the window border with no glass, a frame around a view of the stage), `pips(n, total, c := GOLD_HI, w := 22, h := 8, sep := 4)` (level pips), `tabs(names, cur, f)` (tab strip; gold label and underline on the current tab, `f.call(i)` on another). Glyphs `team`, `pack`, `book`, `bag`.
  - Screens (`UiScreens._screen`) are three zones: header on a scrim, stage, and one sheet window holding every control, groups `SHEET_GAP` (16) apart, `GUTTER` (12) from the screen edge. Exceptions: the title (`_title`) has no sheet window; its bottom group (team pill, plaque, dock) is the `inner`/`outer` sheet zone. The Collection (`_coll`) adds `Ui.el.collSpec`, a glassless window frame laid over the stage band (header bottom + 8 to sheet top - 8, hidden below `Layout.MIN_ROOM`) with `Ui.el.collSpecChip` at its lower left; `Run` scales the title actor to fill it (`_fit_specimen`).
- `Fx.kf(node, dur, frames, o)` / `Fx.stop(node)` / `Fx.animating(node)`: a real-time CSS-keyframe animator (CSS animations ignored hit-stop in TS). Fx draws on CanvasLayer 5, Ui on CanvasLayer 10.
- `Run.debug_show(screen)` opens a screen directly (`coll-trait` / `coll-up` open the Collection on that tab; `Run._show_collection(tab := "cards")`). `scenes/main.gd` takes `-- --shot=<title|team|team-swap|map|reward|upgrade|party|end|pack|coll|coll-trait|coll-up|shop|battle|inspect|flick> [--shot-dir=DIR] [--shot-scroll=PX]` to save a screenshot and quit; run it with `--audio-driver Dummy` on this machine (the default audio driver hangs at startup here).
- Not ported (no visual equivalent worth the cost): `backdrop-filter` blur on panels, the dashed border on bench cards (lighter border instead), CSS `filter: saturate()` on poor/swap-cooldown cards (darkened instead), `text-wrap: balance`.

**Stage (Layout, Feel, Particles, Stage, Actor):**
- Feel drives itself (`_process`, `process_priority -100`, `PROCESS_MODE_ALWAYS`): it sets `Engine.time_scale` from real time and computes the shake every frame. `Feel.apply_shake()` exists but is a no-op, so the main loop needn't call it. Because `hit_stop(t)` is a method, the TS `feel.hitStop` counter is `Feel.hit_stop_left`; `slow`/`slow_scale` keep their names. Stage reads `Feel.shake_px` / `shake_rot` and moves the camera.
- `Particles.update_particles(dt)` is TS `updateParticles` (the main loop calls it). `Particles.tex(name)` returns a TS `TEX` texture. `emit` also accepts `dir` as a `Vector2`.
- `Stage.ambience` = `{fireflies, leaves, neutral}` replaces `getStyle().ambience` (HD-2D is the only style).
- Pedestals are positioned by `Stage.update_scene(t, dt)` itself: it reads `S.em`, `S.mode`, `S.title_actor` and `S.active_actor()`, so the main loop doesn't port TS main.ts's pedestal block. `Stage.debug_peds` overrides that for tests.
- Stage owns a vignette plus upper-left key-light wash on `CanvasLayer -1`, which sits above the 3D view and under the UI's layers 5 and 10.
- Stage mapping helpers for anyone who needs 3D: `Stage.world` (the Node3D root), `STAND_Y`, `to_height(p, h)`, `to_stage(p)`, `to_screen(w)`, `wpp(w)`, `at_z`, `at_depth`, `cam_right/up/back()`. `Layout.measure_band(top, bottom)` treats a negative `bottom` as "no bottom HUD". `Layout.band_spots(top, bottom)` returns where the spots would be. Spots always stay inside the free band; `Layout.room` is false when the band is shorter than `MIN_ROOM` and the title creature is then hidden instead of drawn under a panel.
- Actor extras: `set_aura(color, alpha)` (the core request: a wind-up glow behind the creature), tweenable `flash`, `k`, `art_scale()`, `root_point(art_xy)`, `feet()`, `screen_rect()` (the sprite's screen-px box, for the UI check) and `static prebake(key)` (Noctyrm prebakes all four element recolours on create). `Actor.create(key, el := "")`: an empty `el` means the species' own element.
