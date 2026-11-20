# Features

Overview of what DrumMachine.jl can do. Details are in the [README](README.md) and in [docs/](docs).
Changes per version: [CHANGELOG.md](CHANGELOG.md).

## Grid and patterns

- Grid in 16ths, 8th triplets, 16th triplets, 8ths or 32nds.
- 1 to 32 steps per pattern, so odd meters work (12 steps for 3/4, 20 for 5/4, 28 for 7/4).
- Three dynamics per note: ghost (`o`), normal (`x`), accent (`X`). Each level plays at one loudness, the accent at least 6 dB above normal, the ghost note at least 8 dB below.
- *Human* per song (0 to 100 %): random level (up to ±3 dB) and timing (up to ±10 ms, also early) per hit.
- Ornaments per note: double stroke, buzz roll, flam, drag. Timing per song in ms, volume of the grace notes adjustable.
- Swing from straight to dotted (50 to 80 %), on 8ths or 16ths or automatic. The bar length stays the same: an incomplete swing pair or triplet group at the end of an odd bar is played straight.
- Up to 24 patterns per song, played in a chain (`1x3 2` = 1 1 1 2).
- Own tempo per pattern, so the tempo can change within a song.
- *+ Fill* creates a fill pattern from the current groove, 7 styles. In odd meters kick and accents fall on the beats of the bar.
- 56 presets: rock, pop, country, funk, shuffle, blues, jazz, latin, reggae, hip-hop, R&B, drum and bass, jungle, march, odd meters, one for *Einmessen*.
- Example songs with form, fills and track effects in `songs/`.

## Sound

- 12 tracks: kick, snare, side stick, hi-hat closed, open and pedal, tom 1, tom 2, floor tom, ride, ride bell, crash. Kits recorded with two toms get tom 2 from tom 1, 3 semitones lower.
- Kits from sample libraries (AVL, DrumGizmo, Virtuosity), several velocity layers and round robins, plus 808 and 909 synth kits. BlackPearl is included, the others are downloaded when chosen in the kit menu or with `auto_kits = true` (see [KITS.md](KITS.md)). A failed download stays in the menu for another try; a lock file keeps two DrumMachine processes from building the same kit.
- Gain per kit.
- Per track: volume in dB (off, −30 to +12 dB), mute, solo, left/right swap, 3-band EQ, chorus or flanger. Pan and pitch in the song file.
- Master effects: room, hall, echo (one 8th note at the song tempo), drive, lo-fi. Master volume with soft limiter.
- Hi-hat choke: closed, open and pedal hi-hat cut each other off.

## Playing and practicing

- Pattern mode (loops the pattern being edited) and song mode (plays the chain).
- Count-in, click, tempo 30 to 400 BPM by slider or input field.
- Metronome in its own window: time signatures up to 12/8 with accent groups, subdivisions, accents, 9 sounds (click, beep, woodblock, cowbell, claves, sticks and three kit sounds), gap trainer (play n bars, mute m bars), tempo trainer (+x BPM every n bars).

## E-drum kit: recording, playing through the module, MIDI export

- Hits from an e-drum module are recorded into a new song, connected by USB, no MIDI interface needed. Note table for the Roland TD-27, General MIDI as fallback, own assignments in `[midi_map]`.
- *● Aufnahme* opens a recording window (tempo, grid, bar length 2/4 to 7/4, Start/Stop) readable from the kit. A click plays; recording begins with the first hit, so there is time to get to the kit, and ends after 8 s without a hit. The window shows the bar number and the bar being played.
- Every bar played becomes a chain entry, equal bars share a pattern (at most 24, further bars take the most similar). A hit just before a bar line goes to step 1 of the next bar; two hits on one step keep the louder level.
- Result window with all bars and their patterns; *Übernehmen* loads the recording as a new song and backs up the previous one (`vor_aufnahme.toml`).
- Velocity sets ghost note, normal or accent (thresholds `midi_ghost`, `midi_accent`, per track in `[midi_levels]`).
- *Einmessen*: loads a calibration pattern (80 BPM, hi-hat loud and soft, snare backbeat with ghost notes, kick) and opens a live window readable from the kit: waiting for the first hit, 8 bars warm-up, measuring until a 6 s pause. The result window shows per track the hits along the velocity axis with old and new thresholds and the share recognized, plus a timing histogram; *Übernehmen* saves the thresholds (`[midi_levels]`) and the timing offset (`midi_offset_ms`). The song comes back afterwards.
- Audio output latency is compensated, `midi_offset_ms` for fine tuning; the status line shows each hit's offset in ms.
- MIDI input menu, opened again at the next start. *↻* searches for devices again and rereads the MIDI settings. Notes without a track show their number in the status line.
- *Mithören* plays the kit sound of each hit, delayed by the audio buffer.
- MIDI output (menu *Ausgang*): *Play* sends pattern or song in a loop to the module (channel 10, TD-27 notes, controller 4 before hi-hat notes) instead of the kit sound, timed like the sound card. *Pegel* scales the velocity (10 to 100 %), since the TD-27 does not take MIDI volume. MIDI clock with Start and Stop, so the module's click follows the tempo (TD-27: Sync Mode EXTERNAL). Saved as `midi_out_device` and `midi_out_level`; shared with the setup player.
- Details: [docs/midi.md](docs/midi.md).

## Against crackles and dropouts

- GC pause: Julia's garbage collection (GC) is held during playback for 2 to 20 min, against crackles at fast tempos.
- High priority: `start_drum.sh --prio` (implied by `--player`) runs the program with `nice -15` and the audio thread with realtime priority 70. Needs the group `pipewire` once (`sudo groupadd -f pipewire && sudo usermod -aG pipewire $USER`), no value to enter.
- Audio buffer adjustable (`audio_latency` in the settings file, 0.08 s by default).
- Setup player: songs are rendered in advance, no GC pause needed.
- After an audio device error *Play* and *● Aufnahme* open the sound card again.

## Export

- WAV like an audio CD (44.1 kHz, 16 bit), stereo or mono, left/right swapped if needed.
- Repeats, count-in bars and click as part of the export.
- WAV and MIDI files without count-in start with a pickup bar when step 1 has a flam or drag (a 16th, longer for a long flam or drag at a fast tempo), so the grace notes come before the beat.
- Loop export for drum modules: no count-in, exactly whole bars, decay folded onto the start, flam and drag grace notes before step 1 at the end (Roland TD-27: Loop Type = LOOP).
- ASCII file names for drum modules.
- MIDI file (`.mid`, format 0, channel 10, TD-27 and General MIDI notes) for a DAW or MuseScore, with swing, pattern tempo, time signatures, ornaments, count-in and click (notes 33 and 34). Same settings as the WAV export. Triplet bars that fill whole 8ths get a signature in 8ths (9 steps at 6 per beat give 3/8). Controller 4 before each hi-hat note (127 closed and pedal, 0 open) for Roland modules. The status line warns when a bar has no exact time signature.

## WAV editor

- Cut, copy, paste, delete, crop, silence, reverse, with undo and redo (30 steps, at most 1 GB).
- Fade in and out, normalize, gain, effects (room, hall, echo …), 3-band EQ.
- Insert silence, prepend a count-in, detect the BPM.
- Save as WAV with 16 bit, 24 bit or 32 bit float, or as AAC (.m4a) for messengers.

## Setup player (stage)

- Setup editor: songs (`.toml`), WAV files and MIDI files (`.mid`, `.midi`) in order, saved as setups. Loop WAVs are not accepted.
- MIDI files play like a WAV (pause, beeps, auto mode) but through a MIDI output (menu *MIDI-Ausgang*, e.g. a drum module by USB, saved as `midi_out`). The audio thread sends the notes, timed for the moment the sound card plays the same point, so MIDI files and WAVs in one setup stay in time. Format 0 and 1 with tempo changes. All Notes Off on stop, song change and close.
- Songs are rendered in advance, on stage only finished audio is played.
- Auto mode with pause and 3-2-1 countdown beeps before each song, or manual mode: a click plays the song at once.
- Master volume, 3-band EQ, reverb (room, hall, cathedral).
- Music in mono on one channel, beeps and count-in on the other (for the headphones), or both in stereo.
- Runs on its own (`start_drum.sh --player`, which includes `--prio`: realtime priority for the audio thread if the user has the rights) or from the main window. The status line shows whether realtime priority is active.
- Closing the player stops preparing songs and frees the prepared audio.

## Files and import

- Songs are plain TOML files, readable and editable by hand ([docs/song-format.md](docs/song-format.md)). Invalid values (tempo, grid, repeats, count-in) are corrected on load.
- Songs and exports go to `~/.local/share/DrumMachine/songs` for a package installed with Pkg, to `songs/` for a git checkout or `Pkg.develop`. `song_dir` in the settings file (or `DRUMMACHINE_SONG_DIR`) sets another folder; the example songs are listed as well. A read-only song (e.g. an example song of an installed package) does not turn on edit mode; *Speichern* then writes a new file.
- Edit mode: *Speichern* overwrites the loaded song without asking; an error shows in the status line.
- Drum-JSON import from browser drum machines (OneMotion), several files at once or from the clipboard.
- The last session is restored at start.
- Julia API for scripts: build songs from text rows, presets and fills, render or export them as WAV or MIDI, read and write WAV files ([API reference](https://welthulk.github.io/DrumMachine.jl/dev/api/)).

## Program

- Interface in English and German, follows the system language.
- Built-in help (`?`) and documentation viewer (*Docs*): one button per document, sections longer than 40 lines split into pages, ◀ ▶ and the arrow keys turn pages.
- *Info* window with version, author, date of the last change, the kit licenses and the path of the log.
- Log file `~/.local/state/DrumMachine/drummachine.log` for bug reports: warnings and errors with backtrace, start (version, Julia, system, threads), audio (buffer, reported latency, realtime priority), kits, MIDI devices, recording, calibration, exports, songs. At 1 MB it becomes `drummachine.log.1`, so at most about 2 MB are kept. Scripts using the package write no log.
- Closing the main window also closes the player and the metronome and saves their settings.
- Optional sysimage for a fast start (`start_drum.sh --build`). The script offers a rebuild after package updates or a Julia update.
- Developed and tested on Linux. Windows and macOS are untested, see [PLATFORMS.md](PLATFORMS.md).
