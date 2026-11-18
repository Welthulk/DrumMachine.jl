# Changelog

## Unreleased (1.0.0)

First version for the Julia General registry. Replaces 0.5.0 to 0.9.2, which were withdrawn.

### Added
- Metronome window: time signatures, subdivisions, accents, gap and tempo trainer.
- Drum-JSON import from browser drum machines, also from the clipboard.
- 32nd grid (8 steps per beat).
- Nine free kits (AVL, DrumGizmo), gain per kit.
- Presets and songs: Amen break, Tom-Sawyer style, Wild-Thing style, Double-Time Swing.
- BPM entry field, tempo up to 400.
- GC pause against dropouts at fast tempos.
- The last session is restored at start.
- `start_drum.sh --no-image` starts without the sysimage, `--help` lists the options.
- Ornaments per note: double stroke (`2`), buzz roll (`z`), flam (`f`), drag (`r`). Set them with the *Verzierung* menu. Timing per song in ms (flam, drag, buzz) and volume of the grace notes.
- Own tempo per pattern: field *Tempo* next to *Steps*, saved as `bpm` in the pattern. Tempo changes in song mode and export.
- Setup player for the stage: plays songs and WAV files in order, auto with pauses and 3-2-1 countdown beeps or manual by click. Master volume, EQ, reverb. Music and cues (beeps, count-in) can go to separate channels.
- Setup editor to put setups together. Loop WAVs are not accepted.
- `start_drum.sh --player` starts only the player. `--prio` raises the priority and runs the audio thread in realtime (needs group `pipewire`). Options can be combined.
- L⇄R button per track.
- Presets *DnB: Two-Step*, *DnB: Half-Time*, *DnB: Liquid*, *DnB: Techstep*, *Jungle: Amen-Chops*, *Jungle: Ragga (One Drop / Amen)*.
- Example song *Karnevalsmarsch (Spielmannszug-Stil)* and preset *Marsch: Spielmannszug*.
- Player, setup editor, metronome and WAV editor are compiled into the sysimage.
- Documentation website ([welthulk.github.io/DrumMachine.jl](https://welthulk.github.io/DrumMachine.jl/dev/)) and tests on GitHub Actions.
- API reference in the documentation for all exported functions (`Song`, `render_song`, `export_wav`, `preset`, `make_fill`, `load_wave`, ...).
- Test coverage on Codecov, TagBot for tags and releases.

### Changed
- Drum-JSON import keeps 32nd files at their tempo instead of doubling it.
- File dialogs use kdialog on KDE, so the file filter is preselected.
- Track volume in dB (off, −30 to +12 dB) with the value shown next to the slider. Was a plain factor up to 1.5.
- Up to 24 patterns per song (was 16).
- *Double-Time Swing (Whiplash-Stil)*: new intro, the roll is built up the way you practice it (one stroke, whole notes up to buzz roll). 81 bars.
- Drum-JSON import takes over flams.
- Help (`?`) has two pages now and a section on the start options.
- The audio thread writes to the sound card itself instead of through a helper task of PortAudio.jl.
- Kits are no longer downloaded on first start. They are listed in the kit menu as "(download, size)" and fetched when chosen. `auto_kits = true` brings back the automatic download.
- Unpacking the kits uses `LibArchive_jll`, the AAC export `FFMPEG_jll`. `bsdtar`, `unrar`, `unzip` and `ffmpeg` no longer need to be installed.

### Fixed
- Clicks when the song mode switched patterns.
- WAV export from the main window failed (`safe` not defined).
- Drum-JSON files in the newer OneMotion format (slots as arrays) were imported empty.
