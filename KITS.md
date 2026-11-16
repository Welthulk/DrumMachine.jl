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
