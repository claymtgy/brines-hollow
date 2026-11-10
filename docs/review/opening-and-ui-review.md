# Brine's Hollow: New-Player Opening and UI Review (pre-1.0)

Reviewed 2026-11-09 against the working tree (uncommitted changes included). Nothing in the game was changed.

**How this was tested.** I read the code and ran the real game in Godot 4.7.2 using a scratch screenshot driver. The driver boots `main.tscn` with `--solo` on an isolated world/profile, forces a windowed resolution, sets `content_scale_factor`, then captures every UI surface:

| Run | Window | UI scale | Notes |
|---|---|---|---|
| Steam Deck | 1280x800 | 1.25 (what the Deck preset sets) | logical canvas is only **1024x640** |
| HD | 1600x900 | 1.0 | project default size |
| FHD | 1920x1080 | 1.0 | |
| QHD | 2560x1440 | 1.0 | |
| Native | 2880x1800 | 1.0 | the dev laptop's fullscreen size, main menu only |

The screenshots referenced below are in `docs/review/img/`.

> **Heads-up: the project does not compile right now.** `scripts/boat_manager.gd:351` uses a bare `is_net` (it should be `main.is_net`). This is part of the in-progress ship-fixtures work, so I did not edit it. My screenshots came from a scratch copy with only that one line patched.

---

## Ranked fix list

### P0: blocks or breaks the first session

1. **New players spawn far from Wren and the homestead.** `main.gd:360-361` picks `world.gen.get_random_spawn()` from 13 coastal spawns (`worldgen.gd:213-276`). In four real runs the player landed **148 m, 247 m, 360 m and 517 m** from Wren's pier. The workbench, campfire, bed and chest are also only at the primary spawn (`entity_manager.gd:812-827`). The only pointer to Wren is a 3.2 s toast, "Someone is waving from the pier." (`tutorial.gd:256`), which other toasts quickly overwrite (see 4). The new player also has no chart, so there is no map.
   *Fix:* for a player's **first** spawn in a world (solo, or the first co-op player), use the Homestead Pier spawn. Keep the random coastal spawns for later joiners and respawns, or put Wren where the player lands. If the random spawn stays, add a world-space waypoint or compass marker to Wren until the first chat.
2. **A gamepad cannot open the inventory or the quest log.** `inventory_toggle` and `quest_log_toggle` have keyboard bindings only (`controller_manager.gd:334-335`). The joypad map (`controller_manager.gd:~366-380`) binds View/Back to `snap`. Even so, the help sheet tells pad players "View → inventory" and "J → quest log" (`hud.gd:781-786`), and the glyph table claims View is inventory (`controller_manager.gd:164`). The Keys tab can only rebind keyboard keys. Hand-crafting lives in the inventory, so **pad-only and Deck players are stuck at tutorial step 3, "Tools of the Trade."**
   *Fix:* bind View/Select to `inventory_toggle`, move `snap` to something like a D-pad long-press, and give the quest log a pad route (a hold on View, or a tab inside the inventory). Then make the help sheet read from the real InputMap rather than hard-coded glyphs.
3. **At the Deck preset, the main screens don't fit.** The Deck preset sets `ui_scale = 1.25` (`game_settings.gd:85-86`), and the project has no stretch mode, so the logical canvas becomes 1024x640. The panels have fixed minimum sizes that are larger than that:
   - The main menu's three cards come to about 1,230 px wide (`hud.gd:214, 259, 294`). The title, skin card and bottom rows are cut off (`deck_menu_main.png`).
   - The inventory is set to at least 1040x610 (`inventory_ui.gd:267`). **The whole right page, including Inspect and Hand Crafting, is off-screen** (`deck_ui_inventory.png`), so even keyboard users on Deck can't craft.
   - The build catalogue (920x540, `build_menu_ui.gd:172`) and quest log (980x580, `quest_log_ui.gd:123`) also clip on the right (`deck_ui_build_menu.png`, `deck_ui_quest_log.png`). The quest log's Close button is cut off.
   - Settings (760x560) fits.

   *Fix (pick one):* (a) set the Deck preset to `ui_scale = 1.0`; or (b) better, set `display/window/stretch/mode="canvas_items"` with a 1280x720 base and treat `ui_scale` as a multiplier. Separately, clamp each modal to the viewport (`min(size, viewport*0.95)`) and put its body in a `ScrollContainer`.

### P1: confusing, or a weak hook

4. **Toasts overwrite each other.** `show_toast` replaces the text and resets a 3.2 s timer (`hud.gd:841-843`). On spawn the sequence is "Washed ashore: …", then "Someone is waving from the pier.", then a creature hint. In every run the creature hint won within about 2 s, so the two that matter were never readable. The hint itself, "Gulls eye unattended fish…" (`gull.gd:63`, fired by `creature_net.gd:905`), means nothing to someone who has no fish yet.
   *Fix:* queue toasts (FIFO, with a priority for tutorial or story lines), or stack 2-3 of them. Hold creature hints until the player has the relevant item or event.
5. **Story quests from NPCs who don't exist compete with the tutorial.** `main.gd:336-337` auto-accepts `story_first_hearth` (Elder Brenda) and `story_tide_tackle` (Old Man Corin). Until the player reaches Wren, the HUD tracker shows "Collect 10 Driftwood" and "Catch 2 Silver Mackerel during high tide" (`1080_hud_01_first_frame.png`). Neither NPC is in the world. "Construct and validate an enclosed shelter" (`quest_manager.gd:26`) is unexplained jargon. The player already starts with 15 driftwood, but the objective counts pickups, so it shows 0/10.
   *Fix:* hold Act I until the tutorial finishes or is skipped, and have Wren hand it over in their farewell. Or reword these as journal entries ("A note in your pocket…"). Explain what counts as a valid shelter (walls, roof, door, bed?) in the objective text.
6. **The tracker fades out while the player is still working on the objective.** The tracker fades 7-10 s after any change (`tutorial.gd:208-220`), so mid-objective the player loses the only on-screen reminder. Pinning exists, but it's buried in the quest log.
   *Fix:* keep the active tutorial step pinned until the tutorial is done, and fade only the non-tutorial quests.
7. **The left side of the HUD stacks on top of itself at start.** The help sheet (`hud.gd:751-757`, centre-left), the tracker (`tutorial.gd:107`, fixed y=158) and the landfall banner (`hud.gd:626-629`, fixed y=150-250) all sit in the same band. At the Deck preset the help sheet covers the island-name banner and the tracker, and the toast covers the clock plaque (`deck_hud_01_first_frame.png`, `deck_hud_03_mission_1.png`). The help sheet also stays up for 10 s while the first dialogue is open.
   *Fix:* put the tracker under the clock plaque in one left-column VBox so the two flow together instead of using fixed y values. Show controls contextually (see 12) instead of as a 20-row sheet. Hide the help sheet whenever a dialogue opens.
8. **Bottom bar collisions.**
   - On the Deck canvas, the hotbar overlaps the vitality panel and covers the health and stamina numbers (`deck_hud_01_first_frame.png`).
   - With the hammer equipped there are **two** context plaques: the build banner (`build_menu_ui.gd:103-107`) and the HUD tool line (`hud.gd:1019-1024`). They say the same thing with **contradictory glyphs**: the banner hard-codes `[RMB/B] [Q/E] [Z/X]` (`build_menu_ui.gd:300, 316, 328`) while the HUD shows pad glyphs (`deck_hud_05_hammer.png`).
   - The dialogue box (`dialogue_box.gd:29-30`, bottom −300…−110) overlaps the tool plaque at every resolution (`1440_wren_greeting.png`).

   *Fix:* hide the HUD tool line while the build banner is showing (or merge them), route the banner through `controller.get_glyph`, hide `bottom_bar` while a dialogue is open, and anchor vitality so it can't overlap the hotbar (or shrink the hotbar on narrow canvases).
9. **There is no automatic UI scale for high resolutions.** Without a stretch mode, UI sizes are in raw pixels. At 1440p and up the HUD and dialogue feel small (`1440_wren_greeting.png`), and at the laptop's native 2880x1800 the menu takes up about 37% of the width with 13-14 px labels. `ui_scale` defaults to 1.0 on every PC.
   *Fix:* this is the same change as P0-3(b). Alternatively, default `ui_scale` to `clamp(min(w/1920, h/1080), 1, 2)` on first run.
10. **Pad glyphs appear when the player is using keyboard and mouse.** `_check_initial_devices` (`controller_manager.gd:39-45`) switches to pad glyphs whenever any joypad is connected. On this dev machine every screenshot showed "L Stick / RT / View" even though no pad was used. Many PCs report virtual pads (Steam Input, vJoy, wheels).
    *Fix:* on PC, start with keyboard and mouse and switch on the first real pad input (`track_input_event` already does this). Start with pad glyphs only when Steam Deck is detected.
11. **The main menu doesn't sell the game.**
    - The backdrop is empty sea and grey sky. `_process` orbits `world.gen.spawn`, but no world exists at the menu, so the camera circles open water at (500, 9, 500) (`main.gd:485`; `900_menu_main.png`).
    - The middle card is half empty, and "Delete World" is the same size and weight as "Play Solo".
    - "Last played" shows a raw ISO timestamp (`hud.gd:464`).
    - The IP field always shows `127.0.0.1`.
    - The seed field is the second thing a new player is asked about.

    *Fix:* generate a small fixed vignette for the backdrop (the homestead pier at dawn) or use a pre-rendered image. Make "Continue <world>" or "New World" the single primary button, with seed and world name under an "Advanced" disclosure. Move "Delete World" to a small, de-emphasised spot. Format the date ("Today, 16:36"). Put Join's address field behind the Join button.
12. **Teaching is front-loaded, while many systems are never taught.**
    - *Up front:* a 20-row controls sheet at spawn (`hud.gd:788-793`), six tools on the hotbar, and two seed types and saplings in the bag.
    - *Taught, in order:* dig, place, craft, crab pot, fish, eat, row.
    - *Never taught,* though the player is equipped for them on minute one: **farming** (hoe in slot 4, seeds in the bag, `player.gd:189, 199-203`), **combat** (cutlass in slot 5, while crabs, mudclaws and reavers roam), the **axe and tree felling** (slot 6), **beds and night**, **tide timing**, **storage**, the **sea chart**, **the village and drifters** (only mentioned in Wren's farewell) and **co-op**.
    - *Taught too late:* the sea chart. The minimap only appears with a chart equipped (`hud.gd:960-969`), and the chart recipe is the **final** tutorial reward (`tutorial.gd:64`).
    - *Undercut:* Wren says "Recipes are worth more than gold", but the quest log shows **105 of 137 recipes already known** at minute one (`deck_ui_quest_log.png`). The hand-crafting list is long, and it opens on tools the player already has (`1080_ui_inventory.png`).

    *Fix:* give the player a parchment shore chart at the start. Add short optional missions after "A Warm Belly": "Till & Sow" (hoe and seeds, harvest later), "Fell a Tree" (axe → logs → planks), and "Steady Your Blade" (cutlass vs. a crab, with parry and dodge). Gate most recipes behind discovery so the line about recipes is true. Start the hotbar with only pickaxe, hammer and rod, and hand over the others with the lesson that uses them. That also fixes the empty-slot clutter.
13. **The first-minute mood.** With the CLI seed, the first morning was rain and wind (weather is deterministic from seed and time, `weather_model.gd`), and every run showed "Hungry" at minute 0 (`hud.gd:951-952`). A grey, rainy, hungry start undersells a cosy coastal game.
    *Fix:* force clear weather for the first in-game day of a new world. Show a neutral "No meal" state instead of "Hungry", or start the player with one meal active.

### P2: polish

14. **Tiny text.** Several labels are 10-12 px: equipment captions at 11 px (`inventory_ui.gd:708, 715`), quest card status at 11 px (`quest_log_ui.gd:508`), chart labels at 10-11 px (`minimap.gd:52, 62`), and catalogue costs at 12 px (`build_menu_ui.gd:454, 462`). At 1.0 scale on a 7" Deck or 1440p panel these are hard to read.
    *Fix:* set a 14 px floor (15 px is better) and let `ui_scale` do the rest.
15. **Inventory layout.** The middle page is about 55% empty below the backpack, while Hand Crafting gets a roughly 200 px scroll box (`1080_ui_inventory.png`). The two seed stacks use the same sack icon, so they can't be told apart, and driftwood is a grey cube.
    *Fix:* give crafting the tall column. Use distinct seed icons, or at least a coloured tag on each.
16. **Build catalogue.** Cards show "In Bag: 0 Wood Plank" in red for nearly every block at the start, and the most useful card (Driftwood, 15 in the bag) sits in column 3, which is off-screen on Deck.
    *Fix:* sort affordable blocks first, or add a "Can build now" filter.
17. **Quest log.** The "HUD Tracker: Pinned (Always…)" toggle is the only way to keep the tracker on screen, and its label is truncated. "Recipe Book" is a strange thing to find inside the quest log.
    *Fix:* move the recipe book into the inventory or a crafting tab, and put a pin icon on each quest card.
18. **Settings.**
    - UI scale is buried in an "Interface" tab that has a single slider.
    - The graphics tab has no "reset to defaults".
    - "Render scale (0 = auto)" and "Frame cap (0 = none)" show raw zeros; show "Auto" and "Uncapped" instead. `show` already does this for render scale but not for frame cap (`settings_menu.gd:247-248, 320`).
    - There is no gamepad remapping.

    The other session's dynamic-music work will need a Music volume slider in the Audio tab (`settings_menu.gd:323-327`). Coordinate with them rather than adding it here.
19. **Pause menu.** It has no Controls/Help entry; F1 is the only way to bring the controls sheet back, and the game never mentions that after the first 10 s.
20. **Top-right HUD.** "Solo" plus a crew icon is noise in solo play; show it only in co-op. The chart's "Depth 0.0m • SE" readout is 10 px.
21. **Dialogue.** Esc closes the "Show me around / I know my way" choice without picking either, which is fine. The speaker line is a strong rust colour on parchment; the 18 px body reads well. Consider a portrait or name plate, and a "Continue (F)" hint, because the typed-out text can be skipped with F, but nothing says so.
22. **Wren's marker.** The "!" Label3D (`tutorial.gd:242-250`) is about 0.38 m tall, so it can't be seen beyond roughly 40 m. Pair it with a HUD edge arrow until the first chat.

---

## (a) The opening, minute by minute (as it plays today)

| Time | What the player sees | Problem |
|---|---|---|
| 0:00 | Main menu: three parchment cards over empty sea. The existing save is pre-selected; for a new world a random seed is pre-filled. | No vista and no promise. The seed and world name are the first decisions. |
| 0:05 | "Washing ashore…" loading screen (`hud.gd:519-541`), about 4-5 s. | Fine; flavour lines in the loader would help. |
| 0:10 | Lands on one of 13 coasts, usually 150-500 m from the pier. A controls sheet, a toast, a landfall banner and two story quests all appear at once. Often raining, "Hungry". | Information overload, with no direction. The "someone is waving" toast is lost. |
| 0:10-3:00 | Wanders. The tracker says to collect driftwood and catch mackerel at high tide, then fades. No map. | Very likely to dig and build aimlessly, or to wander off to the coast. A sandbox player won't mind; a guided player will be lost. |
| ~3:00+ | If they find the pier, Wren auto-greets them at 2.8 m. Missions 1-2 (dig 6, place 5) take about a minute each and pay out well. | This is the strongest part: short, verb-first, and each lesson pays out right away. |
| | Mission 3: craft anything. | Keyboard only (P0-2); off-screen on Deck (P0-3). |
| | Missions 4-6: crab pot, fish, eat. | Good, coastal-specific loop. Mission 6 needs the homestead campfire, which is close only if the player found the pier. |
| | Mission 7: row out. Wren rows away, and the player gets the chart recipe. | A great beat, but nothing tells the player where to sail next. |

**What works:** Wren's voice is warm and brief. Each mission is one verb, paid out on return, with the next lesson offered right away. The "!" and "?" markers follow genre conventions. Skipping the tutorial teaches the recipes. Wren rowing away is a memorable send-off. The tide-driven crab pot and salt pan are the game's unique hook and come early, which is right.

**What a player wants after 15 minutes:** a home and a reason to sail. The game has both (village drifters and 27-31 islands), but neither is pointed at until Wren's farewell line. A good next goal would be "build a shelter with a bed, so the first drifter can move in", shown on the tracker with a clear "what counts" checklist, followed by "chart a neighbouring island".

## (b) UI element by element

| Element | Clarity | Layout and scaling | Verdict |
|---|---|---|---|
| Theme (`ui_theme.gd`) | Cohesive driftwood, parchment and brass; the cream-with-outline text reads on any background. | Pixel 9-slices stay crisp. | Strong; keep it. |
| Main menu | Three equal cards dilute the primary action. | Clips at Deck; small at 1440p and up. | Rework (P1-11, P0-3). |
| Loading | Clear. | Fine. | Add tips. |
| Clock, tide and weather | The tide readout ("Tide −1.2 m · low tide") is great and unique. | Fixed top-left. | Good. |
| Vitality | Bars are clear; "Hungry" is misleading at start. | Overlaps the hotbar at Deck. | P1-8, P1-13. |
| Hotbar and tool line | Good, but the tool line is long, and the hammer shows two lines. | Overlaps dialogue and the build banner. | P1-8. |
| Prompt ("F Talk to Wren") | Keycap style is excellent. | Centred under the crosshair. | Good. |
| Toast and banner | The banner looks great. | Single toast slot; fixed y values collide with the help sheet. | P1-4, P1-7. |
| Help sheet (F1) | 20 rows at once is too many; glyphs can be wrong. | 4 columns at 1200 px and up. | P1-7, P1-12, P0-2. |
| Tutorial tracker | Clear. | Fades too soon; fixed y. | P1-6. |
| Dialogue | Readable, with good choices. | Overlaps the bottom HUD. | P1-8, P2-21. |
| Inventory | Rich but dense; crafting is squeezed. | Clips at Deck. | P0-3, P2-15. |
| Build catalogue | Good tabs and cards; too much red "0". | Clips at Deck. | P0-3, P2-16. |
| Quest log | Nice journal framing. | Clips at Deck; truncated toggle. | P0-3, P2-17. |
| Settings and pause | Logical tabs; fits at every size tested. | Scrolls. | P2-18, P2-19. |
| Sea chart / minimap | Lovely, but unavailable early. | 10-11 px text. | P1-12, P2-20. |

## Suggested order of work

1. P0-1 (spawn), P0-2 (pad bindings), P0-3 (stretch mode or Deck scale plus modal clamping). Each is small and has a large effect.
2. P1-4 (toast queue), P1-5 (defer Act I), P1-6 (pin the tutorial step), P1-7 and P1-8 (layout clean-up). This is mostly `hud.gd`, `tutorial.gd` and `build_menu_ui.gd`.
3. P1-12 (starter chart, plus farming, axe and combat lessons, recipe gating), P1-11 (menu), P1-13 (first-day weather).
4. P2 items as polish.

## Re-running the screenshots

The driver script is not in the repo; it is in the reviewer's scratchpad. To reproduce, write a `SceneTree` script that changes to `res://main.tscn`, waits for `Main.player` and `world.ready_for_play`, calls `DisplayServer.window_set_mode(WINDOWED)` and `window_set_size(...)`, sets `root.content_scale_factor`, and then opens `inventory_ui`, `build_menu_ui.open_catalogue()`, `quest_log_ui`, `settings_menu` and `tutorial._intro()` / `_offer(0)` in turn. Run it with `-- --solo --world=<scratch> --profile=<scratch>` so real saves are untouched. This is worth adding as `tools/ui_review_shots.gd` so every resolution and scale can be checked before release.
