# DrumMachine.jl

English | [Deutsch](README.de.md)

Step sequencer in Julia for drum practice: enter a groove, listen to it, export it as WAV and play along.

![Screenshot](docs/screenshot.png)

The user interface is in German. The **?** button opens a short help in German or English.

## Installation

Tested on Linux with Julia 1.13. You need a graphics driver with OpenGL (for GLMakie) and a
sound card. PortAudio is installed by Julia itself.

1. **Install Julia**, easiest with [juliaup](https://github.com/JuliaLang/juliaup):

   ```bash
   curl -fsSL https://install.julialang.org | sh
   ```

2. **Get the repo and install the packages** (takes a few minutes the first time):

   ```bash
   git clone https://github.com/Welthulk/DrumMachine.jl.git
   cd DrumMachine.jl
   julia --project=. -e 'using Pkg; Pkg.instantiate()'
   ```

3. **Optional:** *Datei öffnen …* (open file) needs `zenity` (GNOME) or `kdialog` (KDE),
   e.g. `sudo apt install zenity`.

## Start

```bash
./start_drum.sh
# or: julia -t auto --project=. run.jl
```

Start it from a regular terminal. Environments without OpenGL (e.g. VS Code as Flatpak)
cannot open the window.

Faster start: run `./start_drum.sh --build` once (takes a few minutes). It builds
`build/drummachine.so` with precompiled GLMakie, and `./start_drum.sh` uses it from then on.
Rebuild after package updates, the script tells you when.

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

## Kits

| Kit | Source | License |
|---|---|---|
| BlackPearl | [AVL Drumkits](http://www.bandshed.net/avldrumkits/), included | CC BY-SA 3.0 |
| CrocellKit | [DrumGizmo](https://drumgizmo.org/wiki/doku.php?id=kits%3Acrocellkit), stereo mix by Henry Järvinen | CC BY 4.0 |
| VirtuosityDrums | [Versilian Studios / Karoryfer](https://github.com/sfzinstruments/virtuosity_drums) | CC0 |
| 808 / 909 (Synth) | synthesized | – |

CrocellKit and VirtuosityDrums are too large for the repo and are built once:

```bash
julia --project=. tools/build_crocell.jl       # downloads 561 MB
julia --project=. tools/build_virtuosity.jl    # downloads 1.2 GB
```

## License

Code: [MIT](LICENSE). The samples are licensed as listed above.
