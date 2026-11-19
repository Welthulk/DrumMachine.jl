# Platforms

DrumMachine is developed and tested **on Linux only** (KDE Plasma on Wayland, Julia 1.13).
**Windows and macOS have not been tested.** The main building blocks (Julia, GLMakie, PortAudio)
exist for all three systems, so the core should run there, but some convenience functions rely on
Linux tools. I only test on Linux. If you would like to port DrumMachine to Windows or macOS, you
are very welcome: issues and pull requests are appreciated.

**Julia packages** (installed automatically by `Pkg`):

| Package | Used for |
|---|---|
| GLMakie | window and graphics (needs OpenGL 3.3) |
| PortAudio | sound output (brings its own PortAudio library) |
| PortMidi_jll | MIDI input for recording from an e-drum kit (brings its own PortMidi library) |
| WAV, FLAC_jll | reading samples, WAV export |
| LibArchive_jll | unpacking the downloaded sample kits (bsdtar: zip and rar) |
| FFMPEG_jll | AAC export in the WAV editor |
| JSON | Drum-JSON import |
| PrecompileTools | faster start |
| Downloads, Markdown, Random, TOML | standard libraries |

**External programs** (optional, looked up in `PATH`):

| Program | Used for | Without it |
|---|---|---|
| `zenity` or `kdialog` | file dialogs: open file, JSON import, WAV editor | these dialogs do not open; songs can still be loaded from the lists |
| `xdg-open` | opening links (GitHub, Docs); macOS uses `open`, Windows `start` | links do not open |
| `bash` | `start_drum.sh` with the sysimage | start with `julia -t auto --project=. run.jl` |

**Known gaps for a port:**

- Windows: no file dialogs (only zenity/kdialog are supported); `start_drum.sh` needs Git Bash
  or WSL.
- macOS: zenity is available via Homebrew; OpenGL is deprecated there but still
  available. The GC pause ends below 1 GB of free memory, which macOS often reports even when
  enough RAM is available.
- MIDI recording uses PortMidi, which exists for all three systems; only Linux (ALSA) is tested.
- `start_drum.sh --prio` and the realtime audio thread use Linux scheduling (`nice`, SCHED_FIFO);
  on other systems the program runs with normal priority.
- Settings, built kits and the songs of an installed package are stored in `~/.config` and
  `~/.local/share` (XDG) on every system; the usual places would be `%APPDATA%` on Windows and
  `~/Library/Application Support` on macOS.
