# Kits

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

Only BlackPearl is in the repo; it and the synth kits work right away. **Nothing is downloaded
unless you ask for it:** the other kits are listed in the kit menu as "(download, size)", and
choosing one downloads and builds it in the background (progress in the status line). It then
appears in the kit menu under its name. Built kits go to `~/.local/share/DrumMachine/kits`, the
downloads to `~/.cache/DrumMachine` (can be deleted afterwards).

The *Gain* slider next to the kit menu sets the level of the current kit; it is stored per kit.

With `auto_kits = true` in `~/.config/DrumMachine/settings.toml` the kits up to 1.2 GB
(everything except DRSKit, MuldjordKit, Aasimonster and the Crocell mixes, about 2.2 GB in total)
are downloaded automatically in the background at start. The environment variable
`DRUMMACHINE_NO_KIT_DOWNLOAD` keeps the download off regardless of the setting.
Manual (re)build:

```bash
julia --project=. tools/build_kit.jl            # list of kits
julia --project=. tools/build_kit.jl DRSKit     # build one (or: all)
```
