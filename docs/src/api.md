# API

Everything the GUI does with songs can also be done from a script. The exported functions below
are the public API; names that are not exported (except `DrumMachine.run`) are internal and may
change in a minor release.

```julia
using DrumMachine

song = preset("Rock: 8tel")
song.bpm = 92
song.patterns[2] = make_fill(song.patterns[1], song.steps_per_beat, 2)
song.chain = [1, 1, 1, 2]
save_song("rock92.toml", song)

entry = only(filter(e -> e.name == "BlackPearl", kit_entries()))   # included in the package
kit = get_kit(entry)
export_wav("rock92.wav", song, kit; repeats = 4)
```

## Starting the program

```@docs
DrumMachine
DrumMachine.run
```

## Songs and patterns

```@docs
Song
Pattern
TrackParams
pattern_from_rows
row_string
parse_chain
save_song
load_song
song_seconds
import_drum_json
```

## Presets and fills

```@docs
preset
PRESET_NAMES
make_fill
FILL_STYLES
```

## Kits

```@docs
Kit
kit_entries
get_kit
available_kits
load_kit
synth_kit
```

## Rendering and export

```@docs
render_song
export_wav
ascii_filename
Engine
```

## WAV files

```@docs
Wave
load_wave
save_wave
```
