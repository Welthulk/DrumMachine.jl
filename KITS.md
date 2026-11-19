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
downloads to `~/.cache/DrumMachine` (can be deleted afterwards). If a download or build fails
(from the menu or with `auto_kits`), the kit is listed in the kit menu again and can be retried
without a restart. An interrupted download or unpack is detected and redone at the next try.

Only one process builds a kit at a time: the lock file `~/.cache/DrumMachine/<Kit>.lock` blocks a
second build of the same kit (a second DrumMachine window, or the program plus one of the
`tools/build_*.jl` scripts). The second one reports that another DrumMachine process is building
the kit. A lock left behind by a crashed process is taken over.

Kits in the package's own `kits/` folder take precedence over built kits of the same name in
`~/.local/share/DrumMachine/kits`; a warning names the hidden folder. Older versions built
CrocellKit and VirtuosityDrums into `kits/` of the checkout. Delete those folders or move them to
`~/.local/share/DrumMachine/kits`, otherwise a rebuild has no effect.

The *Gain* slider next to the kit menu sets the level of the current kit; it is stored per kit.

With `auto_kits = true` in `~/.config/DrumMachine/settings.toml` the kits up to 1.2 GB
(everything except DRSKit, MuldjordKit, Aasimonster and the Crocell mixes, about 2.2 GB in total)
are downloaded automatically in the background at start. The environment variable
`DRUMMACHINE_NO_KIT_DOWNLOAD` keeps the download off regardless of the setting.

The program builds a kit when it is chosen in the kit menu (or at start with `auto_kits = true`).
The scripts are for a manual (re)build:

```bash
julia --project=. tools/build_kit.jl            # list of kits
julia --project=. tools/build_kit.jl DRSKit     # build one (or: all)
julia --project=. tools/build_crocell.jl        # CrocellKit
julia --project=. tools/build_virtuosity.jl     # VirtuosityDrums
```
