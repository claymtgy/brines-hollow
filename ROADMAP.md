# Brine's Hollow — Roadmap

> A co-op voxel sandbox about rebuilding a cliffside fishing village where the tide
> decides what you can reach. Cozy by default, dangerous when you choose it.

## Design pillars

Every feature should serve at least one of these. If it serves none, cut it.

1. **The tide is the clock.** Low tide opens the flats, wrecks, fertile mud, and sea caves; high tide takes them back. Time pressure comes from the sea, not from arbitrary countdowns.
2. **Cozy by default, challenge by choice.** Home and town are always safe sanctuaries. Danger lives in places and times you opt into: night caves, open deep sea, storm surges, spring tides, and ancient ruins.
3. **Every threat has more than one answer.** Fight it, lure it, trap it, light it, quench it, sneak past it, or manipulate the tide against it. Combat is never the only path, and never the best-paying one by itself.
4. **Build together, quickly.** Small voxels for detail, prefabs for speed, shared blueprints for co-op. Builders and farmers are as valuable as fighters.
5. **A village that remembers you.** Recruited drifters have homes, jobs, schedules, and stories; your settlement visibly expands from a lonely camp into a thriving port town.
6. **A shared tide for all playstyles (The Symbiotic Loop).** Farmers and cozy cooks provide long-lasting weather-immunity feasts and stamina buffs that allow fighters to survive outer biomes; fighters bring back abyssal minerals, trophies, and exotic seeds for builders and farmers; builders engineer tide mills, aqueducts, and harbor fortifications that empower everyone.


---

## Phase 0 — Prototype ✅ (done)

Built to answer "does the scale, camera and building feel right?"

- 0.18 m voxels (player ≈ 10 voxels tall), 92 m island with tidal flats, terraced cliffs, sea stacks, a sea cave
- Over-the-shoulder camera with terrain collision; auto-step movement; swimming
- Dig / build brushes, 12 prefabs with ghost preview, rotate + grid snap
- Day/night with a sunny-faded palette, ±1.26 m tide, lamps at night
- Host-authoritative co-op, edits sent as commands, late-join edit log

---

## Phase 1 — Foundations & Core Systems

Goal: Tech de-risking and the fundamental data models that every gameplay layer depends on.

| Item | Why | Size | Status |
|---|---|---|---|
| **C++ voxel core** (GDExtension: storage, meshing, raycast, collision, brushes, fill) | GDScript meshing was ~10 ms/chunk; Steam Deck needs headroom | M | ✅ Complete |
| **Archipelago world** — seeded island placement, varied island sizes/biomes, open sea between | Core world shape | L | 🔨 In progress |
| **Expanded Island Scale & Vertical Depth** — Starter Island scaled to ~600m–800m diameter; world height increased from 23m (4 chunks) to 46m–69m (8–12 chunks) | Fits expansive multi-tier village, agricultural fields, and deep subterranean cave networks | M | Planned |
| **Chunk streaming + LOD** — load/unload chunks around players, low-detail distant islands | Memory and GPU scaling | L | ✅ Complete |
| **Dedicated server** — headless Linux build, world persistence, admin config | Villages live on when players log off | L | ✅ Complete (headless `--server`, autosave 30 s) |
| **Chunk-diff sync** — server sends edited chunks on demand instead of replaying an edit log | Scalable network sync | M | ✅ Complete (edited columns at join, then live commands) |
| **Save / load** — per-region chunk diff files + world seed + entity/NPC state | Persistence across play sessions | M | ✅ Complete (terrain, farm, village, boats, lights, player profiles) |
| **Entity layer** (workstations, chests, beds, barber mirror, physical objects) | Proximity interactions, stations, persistent furniture | M | ✅ Complete |
| **Diegetic Parchment Minimap & Chart System** (equipment-gated 3-tier nautical charts, depth soundings, landmark pins) | Navigation, tide contours, and co-op cartography | M | ✅ Complete |
| **Inventory & Resource System** (data-driven definitions, slot limits, stacking, containers) | Foundation for crafting, trade, and building | M | ✅ Complete |
| **Crafting & Culinary Cooking Systems** (workbenches, campfire skillets, hearth cauldrons, smokehouses, salteries, teahouses) | Food buffs, construction materials, and trade provisions | M | ✅ Complete |
| **Vitality Triad (Health, Stamina & Nourishment)** — diet-driven max HP/stamina, non-punitive hunger, exertion curves, comfort rest | Core survival and physical exertion loops without punitive starvation | M | ✅ Complete |
| **Armor & Weapon Equipment System** (damage types, armor slots, weapon swings, recoil/tether physics) | Combat, hunting, and defensive utility | M | ✅ Complete |
| **Character Customizer & Fisherfolk Wardrobe** (voxel-mesh hair, beards, skin tones, oilskins, sou'westers, paperdoll clothing) | Visual identity and player expression in co-op | M | ✅ Complete |
| **Controller support + Steam Deck UI scale** (DualSense, Xbox, Adaptive Triggers, vibration, glyphs) | Handheld validation and tactile nautical feedback from day one | M | ✅ Complete |
| **Settings menu** (sensitivity, FOV, shoulder, keybinds, quality presets) | Player comfort & testing | S | ✅ Complete (Esc menu: controls, graphics presets incl. Steam Deck, UI scale, key rebinding) |
| **Foliage fade near camera** | Visual clarity under trees and kelp | S | ✅ Complete (dithered fade between camera and player) |

### Inventory & Storage Specifications
- **Player Inventory:** 36 slots + 8 quickbar hotkeys + equipment paperdoll (head, chest, legs, boots, backpack, accessory, and dedicated **Map/Cartography slot**).
- **Equipment-Gated Minimap:**
  - To preserve natural coastal immersion, the HUD does not display an omnipresent minimap by default.
  - Equipping a crafted navigational chart into the dedicated **Map Equipment Slot** unlocks a stylized parchment minimap in the corner of the screen.
  - Higher chart tiers progressively reveal topography, bathymetric shallow reefs, dynamic low/high tide boundaries, and discovered cave entrances.
- **Stacking Logic:** 999 for raw voxels/wood/stone; 20 for food/consumables; 1 for gear/tools.
- **Backpack Upgrades:** Canvas Sack (starter) → Driftwood Rucksack (36 slots) → Seal-Leather Bag (44 slots) → Deep-Diver's Waterproof Pack (52 slots, waterproof).
- **Storage Entities:** Watertight Sea Barrels (preserve seafood freshness), Storage Crates, and Shared Town Stockpiles with configurable category filters.

---

## Phase 2 — Core Loop: Life in the Hollow (Farming, Fishing & Crafting)

Goal: A rich, relaxing sandbox loop with no combat required.

### 1. Coastal Agriculture, Husbandry & Cozy Life
- **Soil & Salinity Mechanic:**
  - *Terraced Sweet Soil:* High ground catchment irrigated by freshwater rain cisterns (Shore Wheat, Root Potatoes, Coastal Hops).
  - *Tidal Brackish Flats:* Coastal mud inundated at high tide; ideal for halophytes (Samphire/Sea Asparagus, Tide Kale, Salt-Cranberries).
  - *Salt Pans:* Evaporation basins flooded at high tide to produce Sea Salt for preserving and curing.
- **Aquaculture:** Oyster racks, mussel poles, and fish weirs placed on tidal flats that flood and drain with tides.
- **Crop Hybridization & Fermentation:**
  - Cross-pollination mechanics: planting sweet wheat adjacent to samphire yields *Brackish Rye* (unlocks hearty dark bread and maritime ales).
  - Aging cellars & casks: Cured cheese wheels, aged ales, and pickled preserves whose buffs and trade value scale with aging time.
  - Mangrove Beehives for salt-marsh honey and candle wax.
- **Coastal Animal Husbandry & Working Companions:**
  - *Livestock:* Salt-Goats (agile cliff grazers, milk/cheese), Highland Shore-Sheep (weatherproof wool for sea cloaks), and Puffins/Ducks (down feathers and sea-eggs).
  - *Tameable Working Pets:* River Otters (dive for shellfish and retrieve floating driftwood), Dock Cats (deter pest birds from drying racks), Trained Sea-Hawks (mast lookouts that circle migrating fish schools and sunken wrecks).
- **Storm Protection:** Windbreaks, dikes, and sea walls to shield crops from storm surges.

### 2. Deepened Fishing System
- **Active Angling:**
  - Rod casting distance meter with target water ripple silhouettes.
  - Line-tension and fish-direction mini-game; gear snap thresholds.
  - Tackle tiers: Whittle Bamboo Rod → Ironwood Ocean Rod → Brass-Geared Deep Caster → Abyssal Siren Rod.
  - Bait crafting: Lugworms (dug at low tide), sand fleas, minced fish bait, phosphorescent shrimp.
- **Passive Traps:** Wicker crab pots and lobster cages dropped from docks/rowboats; checked each tidal cycle.
- **Tide & Almanac Species:**
  - Low tide shallow species (Flounder, Tidepool Starfish, Mud Skaters).
  - High tide pelagic species (Silver Mackerel, Sea Bass, Cliff Salmon).
  - Weather & night specifics (Lightning Eels in storms; Ghost Squid on moonless nights).
  - Biome Legendary Fish: Rare trophy catches for village display or secret recipes.

### 3. Crafting, Architecture & Tidal Engineering
- **Crafting Stations:** Workbench, Smokehouse, Kiln, Loom, Brewery, Saltery, Cheese Aging Cellar.
- **Tidal Power & Mechanical Contraptions (Tide Mills):**
  - Undershot water wheels placed in tidal estuaries generate mechanical torque during rising and falling tides.
  - Powers automated machinery: grain mills, lumber sawmills, stone-crushers, and automated de-watering bilge pumps.
- **Water Engineering:** Sluice gates, flood dykes, drainage pipes, and raised stone aqueducts delivering freshwater down to agricultural terraces.
- **Architect & Detailing Tools:**
  - *Mason's Chisel:* Allows rounding block edges, carving decorative corbels, fluting stone pillars, and shaping dynamic roof eaves.
  - *Architect's Drafting Desk:* Box-select player builds to generate physical Blueprint Scrolls that can be traded in-game or exported to Steam Workshop.
  - *Cozy Home Decor:* Wall-mounted fish taxidermy, placeable live-fish glass aquariums, textile dye vats for banners, and custom pottery.

- **Unlockable Recipes ✅ (built):** Each player keeps a recipe book, saved with their profile. Basic recipes are known from the start; the rest are learned:
  - *Discovery:* the first time a key ingredient enters your inventory (a Silver Mackerel teaches Charred Sea Mackerel and the Sea Barrel).
  - *Quests:* Wren's tutorial and story quests teach recipes as rewards.
  - *Drifters:* recruiting a villager teaches their trade (a Smoker-Chef brings smokehouse and hearth recipes).
  - *Recipe scrolls:* merchants sell scrolls; reading one (on pickup) adds the recipe to your book.
  - Stations open a recipe window showing known recipes, ingredients you have/need, and how many are still undiscovered; Tab opens hand crafting.
  - *Next:* rare scrolls in wrecks and sea caves, legendary-fish "secret recipes", a Recipe Book tab in the Field Logbook, and recipe-scroll trading between players.

### 4. Vitality Triad: Nourishment (Hunger), Health & Stamina
- **Nourishment & Satiety (Non-Punitive Hunger):**
  - **The 3-Meal Satiety Stomach:** Players can digest up to 3 distinct food items simultaneously (e.g., Smoked Mackerel + Samphire Clam Chowder + Shore-Wheat Hardtack).
  - **Diet-Driven Vitality:** Rather than punishing players with starvation death (violating Pillar 2: *\"Home is always safe\"*), food functions as an empowering preparation mechanic. Each meal adds a specific bonus to **Max Health**, **Max Stamina**, and **HP Regeneration/sec**, lasting 15 to 30 minutes of real-world time.
  - **No Starvation Death at Home:** When nourishment falls to zero, stats simply revert to baseline unbuffed survival values (25 Base HP, 50 Base Stamina, no passive combat regeneration). Players will never drop dead while tending crops, building homes, or fishing at the pier.
  - **Food Hierarchy & Culinary Crafting:**
    - *Tier 0 (Foraged Shore Bites):* Wild berries, kelp fronds, raw samphire (+5–10 HP, short duration).
    - *Tier 1 (Campfire Skillet):* Roasted Mackerel, charred mushrooms, boiled clams (+15–25 HP, +20 Stamina).
    - *Tier 2 (Hearth Pots & Chowders):* Tidepool Bouillabaisse, Salt-Cured Cod & Kale Stew (+35–50 HP, +40 Stamina, +1.5 HP/s regen).
    - *Tier 3 (Banquets & Tavern Feasts):* Smoked Salmon & Truffle Pie, Glazed Abyssal Crab (+60–80 HP, +60 Stamina, deep cold immunity, diving lung buffs).
- **Health, Damage & Non-Punitive Defeat:**
  - **Damage Sources:** Melee/projectile monster attacks, falls from cliffs, barotrauma pressure damage at deep benthic depths (without diving suit), freezing hypothermia in Arctic currents, and drowning (asphyxiation when air gauge reaches 0).
  - **Natural & Assisted Healing:** Natural HP regeneration ticks continuously while nourished. Sitting near a crackling campfire, hearth, or bathhouse accelerates healing and applies the *\"Sea-Breeze Rested\"* buff (+50% stamina regen, +20% skill gain).
  - **Opt-In Danger & Non-Punitive Defeat:** If health reaches zero, the player faints and awakens safely ashore beside the nearest village hearth, campsite, or home bed. Inventories are never permanently destroyed; items remain secured in a buoyant driftwood sea-chest at the defeat point with an in-world beacon.
- **Stamina, Physical Exertion & Aquatic Fatigue:**
  - **Action Fuel:** Fuels sprinting, double-jumping, heavy tool excavation (quarrying granite/limestone), farming soil tilling, line casting, reeling thrashing fish, rowing against rip currents, and combat actions (dodge rolling, heavy anchor swings, parries).
  - **Exertion & Breathlessness:** Completely draining stamina triggers a brief 2-second \"Out of Breath\" panting state where movement slows and advanced maneuvers are locked.
  - **Aquatic & Current Drag:** Swimming against prevailing tides or undertow drains stamina faster. Exhausting stamina in open water causes the player to tread water sluggishly and burn oxygen 50% faster, making stamina-replenishing drinks (Chicory Kelp Brew, Mint Tea) crucial for maritime divers.
  - **Recharge Mechanics:** Stamina rapidly recharges when walking or standing still; recharge rates are doubled by the Rested buff or when sheltered under dry village roofs during storms.


### 5. Character Customizer & Fisherfolk Wardrobe
- **Voxel Character Architecture:**
  - Chunky stylized aesthetic built at $2\times$ terrain resolution ($U = 0.09\text{ m}$ per character voxel), maintaining the cozy coastal diorama visual identity.
  - Articulated rigid-part mesh rigging (torso, head, neck, shoulders, elbows, hips, knees).
- **Physical Personalization:**
  - **Skin Tones & Complexions:** Weathered coastal complexions (tanned, freckled, pale brine, deep sun-baked), flushed windburned cheeks, and expressive eye colors.
  - **Hair Styles:** Cropped deckhand, wind-tossed waves, sailor's braid, fisherman's topknot, receding harbor-master, side-parted curls, bald with mutton chops.
  - **Facial Hair:** Salt-and-pepper sea captain's beard, trimmed spade beard, bristly walrus mustache, braided sailor goatee, clean-shaven.
- **Coastal Maritime Wardrobe & Outfits:**
  - **Headwear:** Iconic Sou'wester (wide brim with oilskin neck flap), thick wool watch cap / knit beanie, captain's peaked cap, broad straw sun hat, copper diving bell helmet, woven kelp wreath.
  - **Outerwear & Torso:** Heavy waxed oilskin slickers (canary yellow, storm navy, kelp green, brick red), cable-knit Aran fisherman sweaters, patched canvas smocks, deckhand vests, brass-buttoned pea coats.
  - **Pants & Footwear:** High hip waders, rolled-up duck canvas trousers, sea boots with brass buckles, barefoot deck tread.
- **Dynamic In-World Wear & Environmental Reactions:**
  - *Wetness Shader:* Character models darken and glisten when hit by rainfall or breaking surf; dynamically dry off when resting near village campfires or tavern hearths.
  - *Tidal Mud Splatters:* Wading through intertidal mud flats accumulates mud textures on boots and cuffs, washed off by ocean swimming or freshwater showers.
- **Co-op Visual Identity & The Barber Shop:**
  - Distinctive color palette combinations ensure players remain instantly recognizable in 4–8 player co-op sessions.
  - *The Looking Glass & Barber Shop:* Craftable village furniture (Standing Mirror) and recruitable Town Barber NPC allowing players to alter hairstyles, beards, and clothing dyes at any time in town.
- **Visual Equipment Paperdoll:**
  - Equipped backpacks (Canvas Sack $\to$ Driftwood Frame $\to$ Seal Leather $\to$ Diving Gear), tool belts, and accessories visibly render on the character model in real time.


### 6. Coastal Watercraft (Tier 1 Boats)
- **Driftwood Rowboat / Coracle:** Lightweight, manually rowed; agile in shallow tidal flats and narrow sea caves; can be beached or tied to pier bollards.
- **Outrigger Canoe / Sea Skiff:** Fast shallow-draft coastal craft with a small lateen sail and a live-well compartment for fresh fish storage. Allows safe crossing between adjacent islets.

### 7. Wildlife, Livestock & Predators
Life on the islands beyond the player: some of it ambient, some of it hungry. Predators target **livestock and stores, not players**, and every threat has a non-lethal answer (pillar 3).
- **Livestock (prerequisite):** pens and coops as placeable entities; animals need feed, water, shelter and space; happiness drives yield (milk, wool, eggs, down). Server-simulated and saved like other entities.
- **Ambient wildlife:** coastal hares, seals hauled out on the flats at low tide, puffin colonies on sea stacks, otters in kelp beds, herons in salt marshes, migrating whales offshore. Mostly flee; some can be befriended (otters).
- **Predators that raid the farm:**
  - *Red foxes:* den in island woods; at dusk and night they scout for unguarded coops and pens, slip through gaps in fences, and carry off chickens and ducklings. They leave tracks and scattered feathers so you can follow them back to the den.
  - *Stoats:* small and quick; steal eggs from coops.
  - *Gulls (built):* already steal unattended fish.
  - *Sea eagles:* swoop on ducklings and lambs left in the open by day.
  - *Shore rats:* raid unsealed food stores and drying racks after storms.
- **Defences & answers:** proper fences and latched gates (gaps matter), lanterns that keep foxes at bay, guard dogs and dock cats, live-capture traps (relocate a fox to another island), scarecrows for birds, sealed sea barrels for food, and, optionally, combat.
- **Behaviour:** predators path toward the weakest pen, retreat from light and noise, remember defended farms for a few days, and return to dens that can be found and moved on.
- **Difficulty:** *Cozy*: raids only take eggs or feed and never harm animals; *Tidewatch*: occasional losses with clear warnings ("A fox is circling the coop"); *Undertow*: bolder, smarter raids.
- **Co-op:** host/server simulates wildlife; village bells alert everyone when a raid starts.

### 8. Subterranean World & Cave Networks
- **Tidal Sea Caves:** Carved into island cliff faces; entrances fully submerge during high tide. Low tide reveals interior sandy grottos with rare sea-glass, barnacled chests, and hidden passages.
- **Karst Limestone Caverns:** Multi-chamber caverns beneath island plateaus featuring stalactites, glowing moss patches, and subterranean freshwater aquifers that supply village wells.
- **Abandoned Brass Mines & Catacombs:** Ancient pre-deluge extraction tunnels with rickety timber shoring, ore veins (copper, iron, tin), rusted minecarts, and forgotten subterranean workbenches.
- **Flooded Abyssal Sumps:** Deep underwater cave passages connecting inland sinkholes directly to the ocean, requiring diving bells or breath-buff meals to explore.



---

## Phase 3 — Creating & Managing Your Own Village

Goal: Turn an isolated shelter into a bustling, self-sustaining coastal community.

```
[Castaway Camp] ──> [Coastal Hamlet] ──> [Brine Village] ──> [Thriving Port Town]
 (1-3 villagers)      (4-8 villagers)     (9-16 villagers)      (17+ villagers)
```

1. **Founding & Settlement Boundaries:**
   - **Tide Hearth / Town Bell:** Placeable municipal core that claims a town boundary (60m–150m radius).
   - **Zoning:** Designate Residential, Farming/Docks, Refining/Crafting, and Market districts.
2. **Housing & Room Detection:**
   - Dynamic 3D flood-fill algorithm verifies enclosed rooms: solid walls, weatherproof roof, door, bed, light source.
   - Room score (interior volume, furniture, seaside windows) dictates villager happiness and recruitment draw.
3. **Drifter Recruitment:**
   - Rescuing castaways from shipwrecks exposed at low tide.
   - Saving drifters trapped in tidal sea caves before the tide rises.
   - Welcoming immigrant passengers arriving on visiting packet boats.
4. **Villager Jobs & Daily Routines:**
   - **Fisherman:** Tends pier rods and crab pots; supplies the fish barrels.
   - **Farmer / Salt-Raker:** Waters freshwater beds, manages tidal sluices, rakes salt pans.
   - **Carpenter / Mason:** Converts logs and stone into lumber and ashlar; repairs storm wear.
   - **Smoker & Cook:** Prepares communal meals and cured provisions in the town kitchen.
   - **Lamplighter / Tidewatcher:** Lights beacons at sunset; rings the town bell when storms or spring tides approach.
   - **Schedules:** Shift work → lunch gathering → chore time → evening tavern socializing → sleep.
5. **Automated Village Logistics:**
   - Town Stockpile Depots: Villagers deposit harvested yields and retrieve required seeds/tools without micromanagement.
6. **Town Morale & Progression:**
   - Morale driven by food variety, dry housing, and town safety. High morale boosts town production speed by up to 30% and attracts rare master artisans.
7. **Tidal Festivals & Community Banquets:**
   - Seasonal calendar celebrations (*Spring Tide Equinox*, *Night of the Floating Lanterns*).
   - Multi-course community banquets: players submit dishes to communal tables to trigger town-wide prosperity buffs and unlock rare decorative blueprints.
8. **Town Visual Identity & Customization:**
   - Tunable harbor bell chimes (custom melody/pitch), painted heraldic banners/flags, colored glow-glass streetlamps, and wooden directional signposts.
9. **Settlement Maritime Fleet (Tier 2 Boats):**
   - **The Tide-Barge (Flat-Bottom Cargo Vessel):** High-displacement, flat-bottom barge built to haul bulk stone, timber, and building supplies between islands without grounding in tidal mud.
   - **Coastal Sloop / Cutter:** Single-mast sailboat with rudder wheel, 2–4 player capacity, onboard navigation cot, and mounting davits for hauling heavy crab pots.
   - **Harbor Infrastructure:** Wooden piers, mooring bollards, boat sheds, and dry docks for repairing hulls damaged by storms or reefs.

---

## Phase 4 — Commerce, Quests & The First Biome Boss

Goal: Connect the village to the wider world through trade, storytelling, and optional adventure.

### 1. Trading & Economy
- **Selling to Traders:**
  - *Raft Peddler (Early game):* Casual beach trader exchanging tools, cloth, and basic seeds.
  - *Visiting Merchant Galleons (Mid game):* Scheduled trade ships that dock at deep-water piers with lighthouses; buy bulk crates of cured fish, crops, and brass.
  - *Village Market Stalls:* Assign an NPC as Town Purser to sell surplus village products automatically to visitors.
- **Currencies & Barter:** Early barter evolves into *Brass Guilders* (general goods) and *Tide Scrip* (earned via overseas export contracts to buy rare blueprints and charts).

### 2. Quests, In-World Markers & Narrative
- **Quest Givers:**
  - *Elder Brenda (Town Matriarch):* Village growth, civic structures, housing milestones.
  - *Old Man Corin (Blind Lighthouse Keeper):* Folklore, tide anomalies, secrets of ancient bells.
  - *Cartographer Vane:* Island charting, landmark exploration, sea stack beacons.
  - *Town Notice Board:* Dynamic procedural requests from villagers ("Gather 15 Tide Kale for the winter stew").
- **Starter quest — Wren the Wayfarer ✅ (built):** A travelling fisher walks up to new players when they wash ashore and teaches the basics in seven short missions: dig, build, craft, set a crab pot, fish, eat, and row out. Each mission ends by returning to Wren for rewards and new recipes. Per player (local in co-op), saved with the profile, skippable ("I know my way"). Objectives show in an on-screen quest tracker.
- **Diegetic Navigation & The Map Equipment Slot:**
  - Standard gameplay maintains immersion with clean HUD framing, using an in-world brass *Mariner's Compass*, visible rotating beams from built *Lighthouses*, and a hand-sketched *Field Logbook*.
  - **Minimap Enablement via Map Slot:** Equipping a crafted nautical chart into the dedicated **Map Equipment Slot** activates a corner parchment minimap on the HUD.
  - *Tier 1: Parchment Shore Chart* — Island coastlines, player coordinates/heading, and built campfires.
  - *Tier 2: Hydrographic Sea Chart* — Adds bathymetric depth contours, shallow reef hazards, and dynamic low/high tide boundaries.
  - *Tier 3: Master Chronometer Chart* — Adds wind arrows, ocean current streams, distant lighthouse bearings, and co-op player skiff icons.
- **Light Storyline — "What the Tides Uncovered":**
  - Unravel the mystery of the ancient civilization swallowed by the "Great Deluge."
  - Discover 4 ancient Tide Regulators across the archipelago to restore natural balance.

### 3. Combat, Marine Arsenal & Armor Tiers
- **Combat Fundamentals:** Stamina management, directional dodge roll, parry window, hit-stop feedback, and telegraph cues.
- **Armor System & Utility Tiers (Paperdoll: Head, Chest, Legs, Boots, Accessory):**
  - **Tier 1 (Scavenged Coastal Garb):** *Driftwood-Slat Vest & Woven Kelp Mesh* — Lightweight, zero swimming penalty, basic blunt dampening against crab pinches.
  - **Tier 2 (Maritime Working Armor):**
    - *Cured Seal-Leather Suit:* Cured with sea salt and blubber; provides thermal insulation and reduces swimming stamina consumption by 40% in freezing night tides.
    - *Mud-Crab Chitin Carapace:* Harvested from coastal Mud-Claw brutes; high blunt resistance and wave-slam knockdown immunity.
    - *Tide-Gilded Brass Lamellar:* Forged from reclaimed ship brass; superior slashing defense against pirate cutlasses.
  - **Tier 3 (Specialized Biome Protection):**
    - *Spiny Coralmail & Urchin Pauldrons:* Living staghorn coral reflects piercing damage back at attackers (thorns effect); crafted with sea-glass rivets.
    - *Volcanic Basalt Harness:* Forged from Caldera basalt plates; total immunity to boiling sulfur vents and scalding water surges.
    - *Borean Fur & Blubber Parka:* Prevents hypothermia in freezing arctic waters and sub-zero blizzard squalls.
  - **Tier 4 (Abyssal & Deluge Relic Suits):**
    - *Brass-Diver Heavy Bathysphere Rig:* Heavy copper diving helm, weighted boots, and pressurized breastplate; allows walking firmly on the deep seafloor, immune to abyssal crushing pressure.
    - *Leviathan-Scale Cuirass:* Forged from iridescent scales of defeated biome leviathans; grants a water-dash evasion and bioluminescent aura that pacifies abyssal horrors.
- **Weapons & Combat Styles (Marine Arsenal):**
  - **Harpoons & Tridents (Thrust, Throw & Retrieval):**
    - *Flint Harpoon → Whale-Iron Barbed Harpoon → Abyssal Anchor Trident.*
    - *Signature Mechanics:* Thrown with a tethered retrieval line; hooks into large sea monsters to pull them in, or grapples the player to ship hulls and cliff faces. Unhindered underwater drag.
  - **Seafarer's Blades (Cutlasses, Boarding Axes & Machetes):**
    - *Rusty Deck Cutlass → Brass-Hilted Scimitar → Corsair's Damascus Sabre.*
    - *Signature Mechanics:* High-mobility sweeping cleaves, parry-riposte timing windows, cuts through dense underwater kelp canopies and ship rigging.
  - **Anchor Mauls & Bludgeons (Crushing & Voxel Breakers):**
    - *Driftwood War-Club → Lead-Weighted Pier Mallet → Titan Coral Anchor Maul.*
    - *Signature Mechanics:* High stagger, shatters thick crustacean chitin armor, smashes destructible dungeon barriers and brittle reef formations.
  - **Nautical Ranged (Spearguns, Arbalests & Flare Pistols):**
    - *Pneumatic Speargun:* High-velocity underwater quarrels with zero water resistance.
    - *Deck Swivel Arbalest:* Heavy two-handed bolt thrower with multi-target piercing.
    - *Signal Flare Pistol:* Ignites targets, illuminates pitch-black sea caverns, and blinds photophobic subterranean predators.
  - **Trapper & Non-Lethal Control Tools:**
    - *Weighted Throwing Nets:* Entangles and slows agile predators, dragging aquatic beasts to the seafloor.
    - *Iron Spring Cage Traps:* Deployed on tidal flats to capture Mud-Claws automatically when the incoming tide triggers the pressure plate.
  - **Brine Occultism & Tidal Lanterns:**
    - *Phosphor Lantern Staff:* Channels bioluminescent rays to reveal hidden underwater currents, expose invisible cave wraiths, and burn abyssal cultists.
    - *Tide-Chime Tuning Fork:* Emits resonant acoustic pulses that repel piranha swarms and shatter brittle volcanic glass.
- **Four Distinct Combat Archetypes:**
  - *The Heavy Harpooner:* Reach weapon with pull mechanics, impaling strikes, monster tethering to rock pillars, heavy armor.
  - *The Tide Duellist:* Dual cutlasses, parry windows, ripostes, bleed damage, swift mobility.
  - *The Alchemical Trapper:* Deploys net launchers, powder kegs, pressure mines, poison bait, and flash flares.
  - *The Brine Occultist:* Channels ancient tidal energy through lantern-staves—casting water whips, steam blasts, and blinding flash stuns.
- **Biome 1 Boss — The Barnacled Hulk (Goliath Hermit):**
  - *Location:* The Hollow Flats (Starter Biome).
  - *Arena:* A low-tide sinkhole around a shattered ancient galleon hull.
  - *Combat Route:* Harpoon eye-stalks, dodge claw slams, hit soft joints when it emerges to strike.
  - *Non-Combat / Environmental Route:* Collapse overhead limestone pillars with pickaxes/explosives onto the hull, or bait it into sinking tidal mud during the receding tide.
  - *Reward:* *Gilded Ship Wheel* (vessel maneuverability buff), heavy chitin plates for Tier 2 gear.

### 4. Enemies, Hostile Factions & Enemy POI Spawn Points
- **Hostile Factions & Enemy Types:**
  - **Drowned Marauders / Sea-Reavers:** Marooned pirate castaways armed with cutlasses, boarding axes, and crude harpoon throwers; patrol shorelines and coastlines.
  - **Mud-Claw Swarmers & Brutes:** Territorial crustacean biped humanoids defending tidal mudflats, mangrove shallows, and sea caves; armored against slashing, weak to bludgeoning or traps.
  - **Abyssal Cultists / Drowned Priests:** Cloaked fanatics who worship ancient leviathans; cast water surges and summon bioluminescent cave horrors in submerged ruins.
  - **Gloom-Crawlers & Cave Skitterers:** Subterranean cave hunters that ambush from cave ceilings; blind but detect running footsteps and surface vibrations; repelled by bright torchlight.
- **Enemy Villages, Camps & POI Spawners:**
  - **Sea-Reaver Outposts & Smuggler Coves:** Fortified palisades with watchtowers, flare horns, docks with pirate skiffs, and loot caches. Enemies spawn from the camp's *War Horn Totem*; destroying or capturing the totem halts respawns permanently and converts the outpost into a claimable player forward base.
  - **Mud-Claw Hive Mounds:** Shell-and-mud burrow spires on tidal flats that release swarms during low and mid tide.
  - **Sunken Cultist Temples:** Ancient submerged stone plazas and monolithic pillars on outer islets where cultists perform tide rituals.
  - **Infested Subterranean Mine Shafts:** Underground dungeon POIs deep inside cave systems featuring barricaded passages, elite cave marauders, and rich ore hoards.

### 5. Competitive Edge, High-Stakes Trials & Friendly Contests
- **The Undertow Gauntlet (Sunken Arena):**
  - Opt-in high-stakes trial revealed only during lowest spring tides.
  - Battle escalating waves of elite monsters and boss variants against a rising tide timer before the arena floods.
  - Server time-attack leaderboards, Steam leaderboards, and exclusive boss weapon skins/trophies.
- **Opt-in Storm Incursions:**
  - Ringing the village bell tower during violent squalls invites assault by elite Sea-Reaver raiding parties on outer defense towers; high risk, awards top-tier smelting ores and legendary weapon fragments.
- **Friendly Village Competitions:**
  - *Town Sparring Ring:* Zero-death-penalty sand circle in the village for casual and competitive player dueling.
  - *Buoy Regatta Courses:* Placeable floating checkpoint buoys allowing players to create timed obstacle boat races across reefs and currents.



---

## Phase 5 — The Wider Sea: Biomes & Biome Bosses

Goal: Build boats, sail beyond the home atoll, and confront or outsmart the guardians of the outer biomes.

### 1. Nautical Travel & Multi-Tier Vessel Fleet
- **Vessel Progression & Roles:**
  - **Tier 1 (Coastal Skiffs):** *Driftwood Rowboat / Coracle* (shallow navigation, quiet fishing) and *Outrigger Canoe* (fast islet scouting).
  - **Tier 2 (Workboats & Transports):** *Tide-Barge* (high-capacity bulk block/material hauling, shallow-draft) and *Coastal Sloop* (nimble day-sailer with small cabin).
  - **Tier 3 (Deep-Sea Expedition Vessels):** *Ocean Schooner / Ketch* — multi-masted flagship with customizable decks, sleeping berths (sea-spawn / rest), navigation chart table, and deck cooking stove.
  - **Tier 4 (Specialized Biome Vessels):**
    - *The Salvage Diving Tender:* Outfitted with heavy rope winch and brass diving bell to lower players into deep drowned trenches and kelp ruins.
    - *Boreal Icebreaker:* Reinforced ironwood bow and brass rams that crush sea-ice sheets in the Frost-Shoals without taking hull damage.
    - *Basalt Heat-Runner:* Coated in fire-resistant pitch and thermal insulation to navigate scalding volcanic waters in the Basalt Skerries.
- **Modular Voxel Ship Construction:**
  - Standardized boat hulls act as dynamic physical voxel sub-grids: build custom decks, railings, cabin interiors, and place stations (lantern posts, chests, steering wheels, canvas sails, harpoon ballistas, anchor winches).
- **Co-op Sailing & Crew Roles:**
  - Helmsman controls rudder and watches compass; Trimmer angles sails to the wind; Lookout operates fog horn / bell; Deckhands man harpoons and bilge pumps.
- **Maintenance & Damage:**
  - Reef impacts and monster attacks inflict hull leaks; repair at sea with pine tar, oakum, and planks, or dry-dock at village slipways.

### 2. Biomes & Biome Boss Encounters

| Biome | Environmental Flavor & Mechanics | Biome Boss | Encounter Mechanics & Non-Combat Answers |
|---|---|---|---|
| **The Hollow Flats** (Biome 1) | Limestone cliffs, sunlit flats, gentle tide swings, driftwood | **The Barnacled Hulk** *(Colossal Hermit)* | Uses galleon hull as armor; crack with dropped cliff boulders or trap in receding tidal mud. |
| **The Murk-Reef** (Biome 2) | 30m kelp canopy, underwater caves, bio-luminescence, deep trenches | **The Abyssal Siren** *(Caelocanth Leviathan)* | Stalks in murky water with blinding sonic shrieks; stun by igniting underwater phosphor braziers or trap in net lines. |
| **The Basalt Skerries** (Biome 3) | Black volcanic sands, thermal steam geysers, sulfur vents, boiling seas | **The Caldera Shell** *(Ignis-Chelon)* | Superheats surrounding water; breach cold sea sluices during high tide to thermal-shock and crack its molten shell. |
| **The Frost-Shoals** (Biome 4) | Shifting pack ice, sub-zero hypothermia water, glacial arches, blinding fog | **Borean Gore-Fin** *(The Glacial Patriarch)* | Armored twin-tusked whale-beast; bait into charging fragile ice shelves to lodge its tusks; light whale-oil trenches to isolate. |
| **The Maelstrom Spire** (Climax) | Perpetual vortex at the center of the world, ancient submerged ruins | **The Tide Sovereign** *(World Hydro-Engine)* | Climax puzzle-boss encounter: align the 4 biome regulators to calm the world deluge. |

---

## Phase 6 — Polish, Community & Launch

- **Art & Audio Polish:** Style bible consistency pass, dynamic wave & wind audio, cozy orchestral and sea-shanty score.
- **Steam Deck Optimization:** Solid 40–60 fps profile, native 1280×800 UI scaling, gamepad glyphs.
- **Steam Integration:** Steam Networking co-op (NAT traversal), Workshop support for sharing custom village blueprints.
- **Accessibility:** Colorblind-safe palette options, fishing minigame timing assists, full input remapping.

---

## Player Wiki (Markdown in the repo)

A reference players can browse outside the game, kept in `docs/wiki/` as linked Markdown pages (renders on GitHub; can be published to the GitHub Wiki or a static site later).
- **Pages:** Getting Started (what Wren teaches), Controls (keyboard + controller), Tides & Time, Building & Blueprints, Crafting & Recipes (every recipe and how it is unlocked), Farming & Salt Pans, Fishing & Crab Pots, Food & Vitality, Boats & Sailing, Village & Drifters, Merchants & Trade, Creatures & Wildlife, Weather, Difficulty Modes, Co-op & Dedicated Servers, Settings & Steam Deck, FAQ.
- **Generated tables:** a small tool exports items, recipes (with unlock sources), fish (tide/time/weather), crops and creatures straight from the game data, so the wiki never drifts from the code.
- **Upkeep:** update the relevant page with each feature merge; screenshots captured by the existing dev screenshot modes.

---

## Immediate Next Steps

1. **Livestock** (pens, feed, yields): prerequisite for the wildlife and fox raids above.
2. **Wildlife & predators:** ambient animals first, then foxes and stoats raiding pens with lanterns, fences and traps as answers.
3. **Player wiki:** set up `docs/wiki/` and the data-export tool.
4. **Polish from the last merges:** save the bed respawn point in the profile, gamepad mapping for dodge/sneak, merchant stock persistence, eels avoiding placed lantern entities.
