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
| **C++ voxel core** (GDExtension: storage, meshing, raycast, collision, brushes, fill) | GDScript meshing was ~10 ms/chunk; Steam Deck needs headroom | M | 🔨 In progress |
| **Archipelago world** — seeded island placement, varied island sizes/biomes, open sea between | Core world shape | L | Planned |
| **Expanded Island Scale & Vertical Depth** — Starter Island scaled to ~600m–800m diameter; world height increased from 23m (4 chunks) to 46m–69m (8–12 chunks) | Fits expansive multi-tier village, agricultural fields, and deep subterranean cave networks | M | Planned |
| **Chunk streaming + LOD** — load/unload chunks around players, low-detail distant islands | Memory and GPU scaling | L | Planned |
| **Dedicated server** — headless Linux build, world persistence, admin config | Villages live on when players log off | L | Planned |
| **Chunk-diff sync** — server sends edited chunks on demand instead of replaying an edit log | Scalable network sync | M | Planned |
| **Save / load** — per-region chunk diff files + world seed + entity/NPC state | Persistence across play sessions | M | Planned |
| **Entity layer** (doors, chests, stations, crops, traps as objects, not voxels) | NPCs, crafting, farming, and combat need it | M | Planned |
| **Inventory & Resource System** (data-driven definitions, slot limits, stacking, containers) | Foundation for crafting, trade, and building | M | Planned |
| **Controller support + Steam Deck UI scale** | Handheld validation from day one | M | Planned |
| **Settings menu** (sensitivity, FOV, shoulder, keybinds, quality presets) | Player comfort & testing | S | Planned |
| **Foliage fade near camera** | Visual clarity under trees and kelp | S | Planned |

### Inventory & Storage Specifications
- **Player Inventory:** 36 slots + 8 quickbar hotkeys + equipment paperdoll (head, chest, legs, boots, tool belt, accessory).
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
- **Culinary Buffs:** Food eliminates fatigue and grants gentle exploration perks (e.g., +Swim Speed, +Diving Lung Capacity, +Cold/Storm Immunity, +Mining Yield).


### 4. Coastal Watercraft (Tier 1 Boats)
- **Driftwood Rowboat / Coracle:** Lightweight, manually rowed; agile in shallow tidal flats and narrow sea caves; can be beached or tied to pier bollards.
- **Outrigger Canoe / Sea Skiff:** Fast shallow-draft coastal craft with a small lateen sail and a live-well compartment for fresh fish storage. Allows safe crossing between adjacent islets.

### 5. Subterranean World & Cave Networks
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
- **Diegetic Navigation:**
  - No intrusive mini-maps. Navigation uses an in-world brass *Mariner's Compass*, visible rotating beams from built *Lighthouses*, and a hand-sketched *Field Logbook*.
- **Light Storyline — "What the Tides Uncovered":**
  - Unravel the mystery of the ancient civilization swallowed by the "Great Deluge."
  - Discover 4 ancient Tide Regulators across the archipelago to restore natural balance.

### 3. Combat, Archetypes & Starter Biome Boss
- **Combat Fundamentals:** Stamina, dodge roll, parry window, hit-stop, telegraphs.
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

## Immediate Next Steps (Planning & Parallel Tracks)

1. **Tech Core:** Complete native GDExtension voxel engine and verify streaming budgets.
2. **Entity & Inventory Model:** Implement data-driven item definitions, inventory grid, and storage containers.
3. **Farming & Fishing Vertical Prototype:** Implement rod tension loop, tidal mud tiles, and seed planting.
4. **Village Room Detection:** Port flood-fill interior checker for NPC housing validation.
