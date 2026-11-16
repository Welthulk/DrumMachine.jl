# DrumMachine.jl

English | [Deutsch](README.de.md)

Step sequencer in Julia for drum practice: enter a groove, listen to it, export it as WAV and play along.

![Screenshot](docs/screenshot.png)

The interface is available in English and German (buttons *EN* / *DE* in the header; the default
follows the system language). The **?** button opens a short help, *Docs* the documentation.

## Installation

Tested on Linux with Julia 1.13. You need a graphics driver with OpenGL (for GLMakie) and a
sound card. PortAudio is installed by Julia itself.

1. **Install Julia**, easiest with [juliaup](https://github.com/JuliaLang/juliaup):

   ```bash
   curl -fsSL https://install.julialang.org | sh
   ```

2. **Install DrumMachine** from the Julia package registry (once the registration is merged):

   ```bash
   julia -t auto -e 'using Pkg; Pkg.add("DrumMachine"); using DrumMachine; DrumMachine.run()'
   ```

   Your songs and WAV exports are then stored in `~/.local/share/DrumMachine/songs`.

   **Or** get the repository and install the packages (takes a few minutes the first time):

   ```bash
   git clone https://github.com/Welthulk/DrumMachine.jl.git
   cd DrumMachine.jl
   julia --project=. -e 'using Pkg; Pkg.instantiate()'
   ```

3. **Recommended system tools** (Debian/Ubuntu names):

   ```bash
   sudo apt install libarchive-tools zenity ffmpeg
   ```

   - `libarchive-tools` (bsdtar) unpacks the large sample kits on first start
     (alternatives: `unrar` and `unzip`)
   - `zenity` (GNOME) or `kdialog` (KDE) for the file dialogs
   - `ffmpeg` only for AAC export in the WAV editor

## Start

```bash
./start_drum.sh
# or: julia -t auto --project=. run.jl
```

Start it from a regular terminal. Environments without OpenGL (e.g. VS Code as Flatpak)
cannot open the window.

Faster start: if the sysimage `build/drummachine.so` (precompiled GLMakie) is missing,
`./start_drum.sh` asks whether to build it now (takes a few minutes). After that the script reports
at every start whether it found the image, and offers a rebuild after package updates. Build
directly: `./start_drum.sh --build`; start without the image: `./start_drum.sh --no-image`.

More than 40 grooves (rock, funk, shuffle, blues, jazz, latin, odd meters) are available under
*Preset laden*. Worked-out example songs with form, fills and track effects are in `songs/`
(*Eigenen Song laden*).

## Features

- Grid in 16ths, 8th triplets, 16th triplets or 8ths, swing from straight to dotted
- Three dynamics per note: ghost, normal, accent
- Up to 16 patterns per song, chained for song mode and export
- *+ Fill* generates fill patterns in seven styles
- Per track: volume, pan, pitch, 3-band EQ, chorus or flanger
- Master effects: room, hall, echo, drive, lo-fi
- WAV export like an audio CD (44.1 kHz, 16 bit), ASCII file names, count-in and click
- *Loop* export: no count-in, exactly whole bars, decay folded onto the start, so the file loops
  without a gap. On a Roland TD-27 set SONG → [F2] SETUP → Loop Type = LOOP
- *Bearbeiten* (edit) mode: *Speichern* overwrites the loaded song without asking
- Songs are plain TOML files that can be edited by hand, see [docs/song-format.md](docs/song-format.md)
- *WAV-Editor*: edit exported WAVs (cut, trim, fades, normalize, gain, effects, EQ, count-in, BPM
  detection, undo, AAC export for messengers), see [docs/wav-editor.md](docs/wav-editor.md)

  ![WAV editor](docs/wav-editor.png)
- *Metronom* (metronome) window: 30–400 BPM with slider, field and tap tempo, time signatures up to
  12/8 with accent groups, subdivisions (8ths, triplets, 16ths, swing, dotted …), accents (one,
  none, 2 and 4, offbeats), seven click sounds, gap training (play n bars, mute m bars) and a
  tempo trainer (+x BPM every n bars), see [docs/metronome.md](docs/metronome.md)
- *JSON-Import* (Drum-JSON): take over compositions from browser drum machines in JSON format,
  several files at once or Ctrl+V from the clipboard; each is saved as a song
- Play/stop and metronome react with the audio buffer, 0.08 s by default. If it crackles, set e.g.
  `audio_latency = 0.15` in `~/.config/DrumMachine/settings.toml`. Alternatively, *GC-Pause* in the
  transport row halts Julia's garbage collection during playback for up to 2–20 min; it resumes on
  stop, when the time is up or below 1 GB of free memory
- *Info* button: version, licenses, greetings
- *Docs* button: the documentation inside the app

## Kits

| Kit | Source | License |
|---|---|---|
| BlackPearl | [AVL Drumkits](http://www.bandshed.net/avldrumkits/), included | CC BY-SA 3.0 |
| CrocellKit | [DrumGizmo](https://drumgizmo.org/wiki/doku.php?id=kits%3Acrocellkit), stereo mix by Henry Järvinen | CC BY 4.0 |
| VirtuosityDrums | [Versilian Studios / Karoryfer](https://github.com/sfzinstruments/virtuosity_drums) | CC0 |
| RedZeppelin, BlondeBop, BlondeBopHotRods, BuskmansHoliday (percussion) | [AVL Drumkits](http://www.bandshed.net/avldrumkits/) | CC BY-SA 3.0 |
| ShittyKit, Sommerhack (everyday objects) | [DrumGizmo](https://drumgizmo.org/wiki/doku.php?id=kits), stereo mix by DrumMachine.jl | CC BY 4.0 |
| DRSKit, MuldjordKit, Aasimonster | [DrumGizmo](https://drumgizmo.org/wiki/doku.php?id=kits), stereo mix by DrumMachine.jl, on demand | CC BY 4.0 |
| CrocellClose, CrocellStudio, CrocellRoom, CrocellVintage, CrocellLoFi | CrocellKit from the single mics, own mixes (dry … big room, overheads only, lo-fi), on demand ("CrocellMixes", 5.6 GB) | CC BY 4.0 |
| 808 / 909 (Synth) | synthesized | – |

Only BlackPearl is in the repo. **On first start the other kits are downloaded and built
automatically in the background** (about 2.2 GB in total, progress in the status line);
BlackPearl and the synth kits work right away, the others appear in the kit menu as soon as they
are ready. DRSKit, MuldjordKit, Aasimonster (2.4–2.8 GB each) and the Crocell mixes (5.6 GB) are only
downloaded when chosen in the kit menu ("(download, …)"). Built kits go to `~/.local/share/DrumMachine/kits`, the
downloads to `~/.cache/DrumMachine` (can be deleted afterwards).

The *Gain* slider next to the kit menu sets the level of the current kit; it is stored per kit.

To switch the automatic download off, set `auto_kits = false` in
`~/.config/DrumMachine/settings.toml` or the environment variable `DRUMMACHINE_NO_KIT_DOWNLOAD`.
Manual (re)build:

```bash
julia --project=. tools/build_kit.jl            # list of kits
julia --project=. tools/build_kit.jl DRSKit     # build one (or: all)
```

## Settings

`~/.config/DrumMachine/settings.toml` stores the language chosen in the header
(`language = "en"` or `"de"`), `auto_kits` (see above) and the gain per kit (`[kit_gain]`).

## License

Code: [MIT](LICENSE). The samples are licensed as listed above.
