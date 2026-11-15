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
directly: `./start_drum.sh --build`.

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
  tempo trainer (+x BPM every n bars)
- *Docs* button: the documentation inside the app

## Kits

| Kit | Source | License |
|---|---|---|
| BlackPearl | [AVL Drumkits](http://www.bandshed.net/avldrumkits/), included | CC BY-SA 3.0 |
| CrocellKit | [DrumGizmo](https://drumgizmo.org/wiki/doku.php?id=kits%3Acrocellkit), stereo mix by Henry Järvinen | CC BY 4.0 |
| VirtuosityDrums | [Versilian Studios / Karoryfer](https://github.com/sfzinstruments/virtuosity_drums) | CC0 |
| 808 / 909 (Synth) | synthesized | – |

CrocellKit and VirtuosityDrums are too large for the repo. **On first start they are downloaded
and built automatically in the background** (561 MB and 1.2 GB downloads, progress in the status
line); BlackPearl and the synth kits work right away, and the new kits appear in the kit menu as
soon as they are ready. Built kits go to `~/.local/share/DrumMachine/kits`, the downloads to
`~/.cache/DrumMachine` (can be deleted afterwards).

To switch the automatic download off, set `auto_kits = false` in
`~/.config/DrumMachine/settings.toml` or the environment variable `DRUMMACHINE_NO_KIT_DOWNLOAD`.
Manual (re)build:

```bash
julia --project=. tools/build_crocell.jl
julia --project=. tools/build_virtuosity.jl
```

## Settings

`~/.config/DrumMachine/settings.toml` stores the language chosen in the header
(`language = "en"` or `"de"`) and `auto_kits` (see above).

## License

Code: [MIT](LICENSE). The samples are licensed as listed above.
