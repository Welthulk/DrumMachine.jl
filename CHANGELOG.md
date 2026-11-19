# Changelog

## Unreleased (1.1.1)

- Fixed the beat display of the metronome window: the dots were drawn on top of each other.
- Fixed the *Song-Tempo* button of the metronome reaching past the panel.
- Removed the TagBot workflow and the Codecov upload, which need repository secrets. Tags are set after registration.

## 1.1.0 (2026-11-19)

- Added recording from an e-drum kit over MIDI, connected by USB without a MIDI interface. Button *● Aufnahme* and menu *MIDI* in the transport panel, description in `docs/midi.md`.
- Added note table for the Roland TD-27 (heads, rims, edges) with General MIDI notes 35, 39 and 41 as fallback. Own assignments in `[midi_map]` in `settings.toml`.
- Added velocity to level: ghost note below 45, accent from 105, set with `midi_ghost` and `midi_accent`.
- Added latency compensation for recorded hits: the audio output latency is subtracted, `midi_offset_ms` corrects the rest. The status line shows how many ms each hit was off its step.
- Added *Mithören*: MIDI hits also play the kit sound.
- Added MIDI file export: button *MIDI* next to *WAV exportieren* writes `<name>.mid` into the song folder (format 0, channel 10, TD-27 and General MIDI notes) with swing, pattern tempo and ornaments. Script: `export_midi`.
- Added dependency `PortMidi_jll`.
- Added MIDI files (`.mid`, `.midi`) to the setup player. They play like a WAV with pause, beeps and auto mode, but through a MIDI output, e.g. to the drum module by USB, timed with the sound card. Menu *MIDI-Ausgang* in the player, saved as `midi_out` in `[player]`. All Notes Off on stop, song change and close.
- Changed `start_drum.sh --player` to include `--prio`: the player's audio thread runs with realtime priority if the user has the rights. The player's status line shows whether it does.
- Changed the *Docs* window: one button per document at the top, sections longer than 40 lines split into pages, ◀ ▶ and arrow keys to turn pages.
- Added author and date of the last change to the *Info* window.
- Changed the transport panel to 3 rows. Grid rows are 2 px lower so the window keeps its size.
- Added a warning when a kit folder is hidden by a folder of the same name in the package's `kits/` folder, which takes precedence.
- Added `README.de.md` section *Einstellungen* with all keys of `settings.toml`.
- Changed the swing slider to go up to 80 % (was 75 %), as the song format allows.
- Changed the MIDI export: controller 4 on channel 10 before each hi-hat note, 127 for closed (42) and pedal (44), 0 for open (46). Roland modules use it for the hi-hat opening.
- Changed the MIDI export: triplet bars that fill whole 8ths get a signature in 8ths (9 steps at 6 per beat give 3/8). The status line warns when a bar has no exact time signature.
- Changed the WAV editor undo to keep at most 1 GB (still up to 30 steps).
- Changed closing the setup player: it stops preparing songs and frees the prepared audio.
- Changed closing the main window: it also closes the player and metronome and saves their settings. Setup editor and WAV editor stay open.
- Fixed the second stroke of a double and the bounces of a buzz roll on the last step, which were missing from WAV and MIDI export.
- Fixed a flam or drag on step 1 in exports without count-in and in loop exports, where the grace notes played together with the main stroke. Loop exports put them at the end of the file, WAV and MIDI files without count-in start with a pickup bar of a 16th (longer for a long flam or drag at a fast tempo).
- Fixed swing making bars with an odd number of swing steps longer (e.g. 7/8 with 8th swing). The last unpaired step is played straight.
- Fixed the master echo, which repeated every 250 ms. It now repeats on 8th notes of the song tempo, and WAV exports keep all repeats at slow tempos.
- Fixed the metronome display delay, which now uses the output latency the sound card reports.
- Fixed audio that could not be restarted after an audio device error. *Play* and *● Aufnahme* reopen the sound card, and the window no longer hangs after 64 clicks on the grid.
- Fixed songs and exports of a package installed with Pkg, which were saved inside `~/.julia/packages` and lost on update. They go to `~/.local/share/DrumMachine/songs`.
- Fixed *Speichern* failing silently. An error now shows in the status line.
- Fixed loading a read-only example song turning on edit mode. *Speichern* then writes a new file in the song folder.
- Fixed deleting a pattern during song playback, which changed the playing order.
- Fixed the *Steps* menu for step counts it does not list (e.g. 11): it shows the count and accepts any choice.
- Fixed song lengths like 59.7 s showing as 0:00 instead of 1:00.
- Fixed swing and tempo values like 0.8, 0.625 or 120.5 BPM being rounded by the sliders after loading a song.
- Fixed *WAV exportieren*: "Exportiere …" shows during the export, and clicks during an export are ignored.
- Fixed *+ Fill* in odd meters (e.g. 7/8 with 14 steps): kick and accents of the fill land on the beats of the bar.
- Fixed songs with `bpm = 0`, a negative `countin` or an invalid `steps_per_beat`, which stopped playback and export. Values are corrected on load: `bpm` 30 to 400, `repeats` 1 to 999, `countin` 0 to 4.
- Fixed rows longer than `steps` in a song file: the extra notes are dropped on load, as documented.
- Fixed an interrupted save leaving a truncated song file. `save_song` writes a temporary file first.
- Fixed `start_drum.sh` starting with a sysimage that no longer loads after a Julia update (juliaup). The image now also counts as stale after a Julia update, and `tools/build_sysimage.jl` writes `build/manifest.key` itself, so a direct build is recognized. Existing images are offered for rebuild once.
- Fixed Drum-JSON import: integer `shuffle` codes, variants and flams on repeated tracks, `null` as name or kit, hi-hat sounds named closed (closed hi-hat, was pedal).
- Fixed an interrupted kit download or unpack being taken as complete at the next build.
- Fixed a failed kit build that could leave the kit half deleted.
- Fixed a failed kit download (menu or `auto_kits`) not showing up in the kit menu again for a retry.
- Fixed two processes building the same kit at the same time. The lock file `~/.cache/DrumMachine/<Kit>.lock` blocks the second one.
- Fixed WAV editor times of 1 minute or more showing as "1:0005.0".
- Fixed *BPM erkennen* in the WAV editor failing after Shift+click past the end of the file.
- Fixed the setup editor's *Speichern* overwriting the pause and beep set in the player.
- Fixed the *Docs* window crashing on a Markdown file with only a title.
- Fixed the metronome hint "0 = aus" next to the max BPM field. It belongs to the step: *Tempo-Trainer (+0 = aus)*.

## 1.0.0 (2026-11-18)

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
