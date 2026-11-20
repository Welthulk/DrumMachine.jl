# Supporting DrumMachine.jl

DrumMachine.jl is a hobby project. I do not take money for it. If you want to help, these are
the things that move it forward.

## Testing

I only test on Linux (KDE Plasma, Wayland). Reports from other setups are very useful:

- Linux distributions, desktops and sound systems other than mine (GNOME, X11, JACK, plain ALSA).
- Audio interfaces and drum modules: does the WAV export load and loop correctly on yours?
- Long sessions on stage with the setup player (`./start_drum.sh --prio --player`).

Please open an [issue](https://github.com/Welthulk/DrumMachine.jl/issues) with your system,
Julia version, audio device and the steps that lead to the problem, and attach the log
`~/.local/state/DrumMachine/drummachine.log` (path also in the *Info* window).

## Porting to Windows and macOS

The core should run there, the gaps are listed in [PLATFORMS.md](PLATFORMS.md): file dialogs,
unpacking the kits, the start script, the folders for settings and songs. Pull requests are
welcome, also partial ones (for example only the file dialogs on Windows).

## Grooves and songs

New presets and example songs are welcome as TOML files ([docs/song-format.md](docs/song-format.md)).
Please only your own grooves, no transcriptions of copyrighted songs.

## Hardware

Testing the export and the player on real drum modules and pads helps a lot. If you can lend
hardware for a while, please get in touch through an issue.
