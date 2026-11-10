# CC0 Soundscape & Ambience Guide for Brine's Hollow

Brine's Hollow features a dual-layer audio architecture:
1. **Mathematical Synthesis (Default)**: Out-of-the-box, the game synthesizes seamless procedural wave surf, dynamic wind gusts, rain impacts, distant delayed thunder, boat hull water lapping, underwater trench pressure rumbles, and brass victory fanfares with **zero external files or asset dependencies**.
2. **Drop-in CC0 High-Fidelity Override**: If high-resolution real-world audio recordings are dropped into `res://audio/ambience/`, `AmbientAudio` automatically detects them at startup and substitutes them seamlessly with looped streaming playback.

---

## Directory Structure
Place downloaded audio files (.wav or .ogg) into:
```
res://audio/ambience/
├── surf.wav (or surf.ogg)         # Shoreline breaking waves & wash
├── wind.wav (or wind.ogg)         # Coastal breeze and gale gusts
├── rain_ground.wav                # Rain hitting sand, rocks, and mud
├── rain_roof.wav                  # Muffled rain drumming on wooden roofs
├── underwater.wav                 # Submerged deep-sea trench ambience
└── thunder.wav                    # Distant rolling lightning thunderclaps
```

---

## Curated CC0 (Public Domain) Sound Recommendations

All sources listed below are released under **Creative Commons 0 (CC0 1.0 Universal - Public Domain)**, meaning they require no attribution and are completely free for commercial and non-commercial game distribution.

### 1. Ocean Waves & Shoreline Surf (`surf.wav`)
* **"Calm Ocean Waves" by SamsterBirdies**
  * *Description*: Whidbey Island coastal tide washing onto smooth stones and wet sand with natural receding wash.
  * *License*: CC0
  * *Search Freesound*: `https://freesound.org/people/SamsterBirdies/sounds/` or query `"Calm ocean waves"` (filter: CC0).
* **"Ocean Waves Shore" by zenosounds**
  * *Format*: 48 kHz / 24-bit stereo WAV.
  * *Search Freesound*: `https://freesound.org/people/zenosounds/sounds/` (filter: CC0).

### 2. Coastal Wind & Gales (`wind.wav`)
* **"Cold Wind Loop" by InspectorJ**
  * *Description*: Steady wind gusting through coastal headlands without microphone clipping.
  * *License*: CC0 / Public Domain
  * *Search Freesound*: `wind loop cold coastal` (filter: CC0).

### 3. Coastal Rain (`rain_ground.wav` & `rain_roof.wav`)
* **"Rain on Ground / Wet Sand" by straget**
  * *Description*: Soft, steady rainfall without thunder or birds chirping.
  * *License*: CC0
* **"Muffled Rain on Wooden Shingles / Cabin" by Soundscape_HQ**
  * *Description*: Low-passed interior drumming of rain on timber planks.
  * *License*: CC0

### 4. Underwater Deep-Sea Trench (`underwater.wav`)
* **"Hydrophone Deep Ocean Ambience" by Tim_Kahn**
  * *Description*: Submerged hydrophone recording capturing deep pressure swells, muffled fluid motion, and oceanic resonance.
  * *License*: CC0
  * *Search Freesound*: `hydrophone deep water loop` (filter: CC0).

### 5. Rolling Sea Thunder (`thunder.wav`)
* **"Distant Rolling Thunderclap" by ERH**
  * *Description*: Sharp low-frequency initial crack followed by a 4-second echoing low-end roll across the water.
  * *License*: CC0
