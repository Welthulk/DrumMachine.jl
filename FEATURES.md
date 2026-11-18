# Features

Overview of what DrumMachine.jl can do. Details are in the [README](README.md) and in [docs/](docs).
Changes per version: [CHANGELOG.md](CHANGELOG.md).

## Grid and patterns

- Grid in 16ths, 8th triplets, 16th triplets, 8ths or 32nds.
- 1 to 32 steps per pattern, so odd meters work (12 steps for 3/4, 20 for 5/4, 28 for 7/4).
- Three dynamics per note: ghost (`o`), normal (`x`), accent (`X`).
- Ornaments per note: double stroke, buzz roll, flam, drag. Timing per song in ms, volume of the grace notes adjustable.
- Swing from straight to dotted (50 to 80 %), on 8ths or 16ths or automatic.
- Up to 24 patterns per song, played in a chain (`1x3 2` = 1 1 1 2).
- Own tempo per pattern, so the tempo can change within a song.
- *+ Fill* creates a fill pattern from the current groove, 7 styles.
- 55 presets: rock, funk, shuffle, blues, jazz, latin, hip-hop, drum and bass, jungle, march, odd meters.
- Example songs with form, fills and track effects in `songs/`.

## Sound

- 11 tracks: kick, snare, side stick, hi-hat closed, open and pedal, tom, floor tom, ride, ride bell, crash.
- Kits from sample libraries (AVL, DrumGizmo, Virtuosity), several velocity layers and round robins, plus 808 and 909 synth kits. BlackPearl is included, the others are downloaded when chosen in the kit menu (see [KITS.md](KITS.md)).
- Gain per kit.
- Per track: volume in dB (off, −30 to +12 dB), mute, solo, left/right swap, 3-band EQ, chorus or flanger. Pan and pitch in the song file.
- Master effects: room, hall, echo, drive, lo-fi. Master volume with soft limiter.
- Hi-hat choke: closed, open and pedal hi-hat cut each other off.

## Playing and practicing

- Pattern mode (loops the pattern being edited) and song mode (plays the chain).
- Count-in, click, tempo 30 to 400 BPM by slider or input field.
- Metronome in its own window: time signatures up to 12/8 with accent groups, subdivisions, accents, 9 sounds (click, beep, woodblock, cowbell, claves, sticks and three kit sounds), gap trainer (play n bars, mute m bars), tempo trainer (+x BPM every n bars).

## Against crackles and dropouts

- GC pause: Julia's garbage collection (GC) is held during playback for 2 to 20 min, against crackles at fast tempos.
- High priority: `start_drum.sh --prio` runs the program with `nice -15` and the audio thread with realtime priority 70. Needs the group `pipewire` once (`sudo groupadd -f pipewire && sudo usermod -aG pipewire $USER`), no value to enter.
- Audio buffer adjustable (`audio_latency` in the settings file, 0.08 s by default).
- Setup player: songs are rendered in advance, no GC pause needed.

## Export

- WAV like an audio CD (44.1 kHz, 16 bit), stereo or mono, left/right swapped if needed.
- Repeats, count-in bars and click as part of the export.
- Loop export for drum modules: no count-in, exactly whole bars, decay folded onto the start (Roland TD-27: Loop Type = LOOP).
- ASCII file names for drum modules.

## WAV editor

- Cut, copy, paste, delete, crop, silence, reverse, with undo and redo.
- Fade in and out, normalize, gain, effects (room, hall, echo …), 3-band EQ.
- Insert silence, prepend a count-in, detect the BPM.
- Save as WAV with 16 bit, 24 bit or 32 bit float, or as AAC (.m4a) for messengers.

## Setup player (stage)

- Setup editor: songs (`.toml`) and WAV files in order, saved as setups.
- Songs are rendered in advance, on stage only finished audio is played.
- Auto mode with pause and 3-2-1 countdown beeps before each song, or manual mode: a click plays the song at once.
- Master volume, 3-band EQ, reverb (room, hall, cathedral).
- Music in mono on one channel, beeps and count-in on the other (for the headphones), or both in stereo.
- Runs on its own (`start_drum.sh --player`) or from the main window.

## Files and import

- Songs are plain TOML files, readable and editable by hand ([docs/song-format.md](docs/song-format.md)).
- Edit mode: *Speichern* overwrites the loaded song without asking.
- Drum-JSON import from browser drum machines (OneMotion), several files at once or from the clipboard.
- The last session is restored at start.
- Julia API for scripts: build songs from text rows, presets and fills, render or export them as WAV, read and write WAV files ([API reference](https://welthulk.github.io/DrumMachine.jl/dev/api/)).

## Program

- Interface in English and German, follows the system language.
- Built-in help (`?`) and documentation viewer (*Docs*).
- Optional sysimage for a fast start (`start_drum.sh --build`).
- Developed and tested on Linux. Windows and macOS are untested, see [PLATFORMS.md](PLATFORMS.md).
