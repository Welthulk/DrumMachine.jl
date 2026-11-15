# Song file format

A song is a plain [TOML](https://toml.io) file, by default in `songs/<name>.toml`. Everything the
program knows about a song is stored there: tempo, grid, patterns, chain, kit, master effect, the
per-track mixer and effects (EQ, chorus, flanger) and the export settings. The files are meant to be
read and edited by hand.

All keys are optional. A missing key gets the default listed below, so a minimal song is just:

```toml
[[pattern]]
    [pattern.rows]
    HiHat = "x.x.x.x.x.x.x.x."
    Snare = "....X.......X..."
    Kick  = "X.......X.X....."
```

> **Comments are lost when saving.** You can add `#` comments when editing a file by hand (the
> example songs do), but *Speichern* (save) in the program rewrites the whole file without them.

## Song settings (top level)

| Key | Type | Default | Meaning |
|---|---|---|---|
| `name` | string | `"Neu"` | Song name, also used for the file names of save and export |
| `bpm` | number | `100.0` | Tempo in beats per minute (GUI range 30–260) |
| `steps_per_beat` | integer | `4` | Grid: `4` = 16ths, `3` = 8th triplets, `6` = 16th triplets, `2` = 8ths |
| `swing` | number | `0.5` (`2/3` for triplet grids) | Position of the off-beat note within its group: `0.5` straight, `0.667` triplet, `0.75` dotted (used range 0.5–0.8) |
| `swing_on` | integer | `0` | What swings in a straight grid: `0` auto, `8` 8ths, `16` 16ths |
| `swing_version` | integer | `1` | Written as `2` by current versions. Files without it that use a triplet grid and `swing = 0.5` are read as exact triplets (compatibility with v0.1) |
| `chain` | array of integers | `[1]` | Pattern order for song mode and export, 1-based. Invalid numbers are dropped |
| `kit` | string | `"CrocellKit"` | Kit name: a folder in `kits/` (e.g. `BlackPearl`) or `808 (Synth)` / `909 (Synth)`. If the kit is not installed, the program keeps the current kit |
| `fx` | string | `"Clean"` | Master effect: `Clean`, `Room`, `Hall`, `Echo`, `Drive`, `Lo-Fi` |
| `fxmix` | number | `0.25` | Amount of the master effect, 0–1 |
| `master` | number | `0.8` | Master volume, 0–1.5 (soft limiter after it) |

### Export settings

| Key | Type | Default | Meaning |
|---|---|---|---|
| `repeats` | integer | `8` | How often the chain is written into the WAV |
| `countin` | integer | `1` | Count-in bars before the song (ignored with `loop`) |
| `click` | boolean | `false` | Mix a metronome click into the export |
| `mono` | boolean | `false` | Mono output (playback and export) |
| `swap_lr` | boolean | `false` | Swap left and right channel (playback and export) |
| `loop` | boolean | `false` | Seamless loop export: no count-in, exactly whole bars, decay folded onto the start |

## Patterns

Each `[[pattern]]` table is one pattern; their order gives the pattern numbers 1, 2, 3, … used in
`chain`. Up to 16 patterns can be edited in the program.

```toml
[[pattern]]
steps = 16
    [pattern.rows]
    HiHat  = "x.x.x.x.x.x.x..."
    HHOpen = "..............X."
    Snare  = ".o..X..o.o..X..o"
    Kick   = "X..x..x..x....x."
```

| Key | Type | Default | Meaning |
|---|---|---|---|
| `steps` | integer | `16` | Length of the pattern in steps, 1–32. Patterns of one song may differ (e.g. `8` steps for a 2/4 bar in a 4/4 song) |
| `rows` | table | empty | One string per track, one character per step |

Characters in a row:

| Character | Level |
|---|---|
| `.` (also `-`, `_`, space) | off |
| `o` | ghost note |
| `x` (also `*`) | normal |
| `X` (also `#`) | accent |

Rows of tracks without any note are left out when saving. A row longer than `steps` is cut off,
a shorter one is filled with rests.

### Track names

| Key | Instrument |
|---|---|
| `Kick` | bass drum |
| `Snare` | snare |
| `Rim` | side stick |
| `HiHat` | closed hi-hat |
| `HHOpen` | open hi-hat |
| `HHPedal` | hi-hat pedal |
| `Tom` | tom |
| `FloorTom` | floor tom |
| `Ride` | ride |
| `RideBell` | ride bell |
| `Crash` | crash |

Unknown track names are ignored with a warning.

## Tracks: mixer and effects

Each `[track.<name>]` table holds the mixer settings and effects of one track (names as above).
The program writes a table for every track. EQ and modulation keys appear only when the effect is
active, so a track without effects looks like this:

```toml
[track.Snare]
vol = 1.0
pan = 0.0
pitch = 0.0
mute = false
solo = false
```

| Key | Type | Default | Meaning |
|---|---|---|---|
| `vol` | number | `1.0` | Volume, 0–1.5 |
| `pan` | number | `0.0` | Panorama offset from the kit's own panning, -1 (left) … 1 (right) |
| `pitch` | number | `0.0` | Tuning in semitones |
| `mute` | boolean | `false` | Muted (also in the export) |
| `solo` | boolean | `false` | Solo (also in the export) |

### EQ

Three bands per track. The EQ is active as soon as one gain is not 0.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `eq_low` | number | `0.0` | Low shelf at 120 Hz, in dB (-12 … +12) |
| `eq_mid` | number | `0.0` | Mid bell, in dB (-12 … +12) |
| `eq_mid_freq` | number | `800.0` | Frequency of the mid bell in Hz (200–6000) |
| `eq_high` | number | `0.0` | High shelf at 5 kHz, in dB (-12 … +12) |

### Chorus / flanger

| Key | Type | Default | Meaning |
|---|---|---|---|
| `mod` | string | `"Aus"` | `Aus` (off), `Chorus` or `Flanger`. The value names follow the German GUI |
| `mod_mix` | number | Chorus `0.8`, Flanger `1.0` | Effect amount, 0–1 (1 = equal dry and wet) |
| `mod_rate` | number | Chorus `0.8`, Flanger `0.3` | LFO speed in Hz |
| `mod_depth` | number | Chorus `0.8`, Flanger `0.9` | Modulation depth, 0–1 |
| `mod_feedback` | number | Chorus `0.0`, Flanger `0.75` | Feedback, 0–0.9 (higher = more metallic) |

When `mod` is set, the defaults of that effect apply to every `mod_*` key that is missing.

Example: flanger on the crash and a scooped bass drum.

```toml
[track.Crash]
vol = 0.85
pan = -0.2
mod = "Flanger"
mod_mix = 1.0
mod_rate = 0.15
mod_depth = 1.0
mod_feedback = 0.8

[track.Kick]
eq_low = 5.0
eq_mid = -6.0
eq_mid_freq = 400.0
eq_high = 5.0
```

## Complete example

The files in [`songs/`](../songs) are complete, commented examples. A short one:

```toml
name = "Two Bar Groove"
bpm = 96.0
steps_per_beat = 4
swing = 0.5
chain = [1, 1, 1, 2]
kit = "BlackPearl"
fx = "Room"
fxmix = 0.3
master = 0.8
repeats = 4
countin = 1
loop = false

[[pattern]]
steps = 16
    [pattern.rows]
    HiHat = "x.x.x.x.x.x.x.x."
    Snare = "....X..o....X..."
    Kick  = "X.......X.X....."

[[pattern]]
steps = 16
    [pattern.rows]
    HiHat    = "x.x.x.x.x.x....."
    Snare    = "....X..o....Xxx."
    FloorTom = "...............X"
    Kick     = "X.......X.X....X"

[track.HiHat]
vol = 0.9
pan = 0.15
```
