# DrumMachine.jl

[English](README.md) | Deutsch

Step-Sequencer in Julia zum Schlagzeug-Üben: Groove eintragen, vorhören, als WAV exportieren und mitspielen.

![Screenshot](docs/screenshot.png)

## Installation

Getestet unter Linux mit Julia 1.13. Gebraucht werden ein Grafiktreiber mit OpenGL (für GLMakie)
und eine Soundkarte. PortAudio bringt Julia selbst mit.

1. **Julia installieren**, am einfachsten mit [juliaup](https://github.com/JuliaLang/juliaup):

   ```bash
   curl -fsSL https://install.julialang.org | sh
   ```

2. **Repo holen und Pakete installieren** (dauert beim ersten Mal einige Minuten):

   ```bash
   git clone https://github.com/Welthulk/DrumMachine.jl.git
   cd DrumMachine.jl
   julia --project=. -e 'using Pkg; Pkg.instantiate()'
   ```

3. **Optional:** Für *Datei öffnen …* braucht es `zenity` (GNOME) oder `kdialog` (KDE),
   z. B. `sudo apt install zenity`.

## Start

```bash
./start_drum.sh
# oder: julia -t auto --project=. run.jl
```

Wichtig: aus einem normalen Terminal starten. In Umgebungen ohne OpenGL (z. B. VS Code als
Flatpak) öffnet sich kein Fenster.

Schneller Start: einmalig `./start_drum.sh --build` ausführen (dauert einige Minuten). Das baut
`build/drummachine.so` mit vorkompiliertem GLMakie, danach nutzt `./start_drum.sh` das Image
automatisch. Nach Paket-Updates neu bauen, das Skript weist darauf hin.

**Loop-Export:** Schalter *Loop* in der Export-Zeile. Die WAV hat dann keinen Einzähler, ist exakt
ganze Takte lang, und das Ausklingen wird auf den Anfang gefaltet. So läuft sie ohne Lücke in
Schleife. Am Roland TD-27: SONG → [F2] SETUP → Loop Type = LOOP.

**Song-Dateien:** einfache TOML-Dateien, auch von Hand editierbar. Alle Felder inklusive Master- und
Spur-Effekten beschreibt [docs/song-format.md](docs/song-format.md) (englisch).

**Bearbeiten:** Nach dem Laden eines eigenen Songs ist der Schalter an, *Speichern* überschreibt die
Datei dann ohne Rückfrage.

Die Bedienung erklärt der **?**-Button im Programm. Über 40 Grooves (Rock, Funk, Shuffle, Blues, Jazz, Latin, ungerade Taktarten) liegen unter *Preset laden*,
ausgearbeitete Beispiel-Songs mit Form, Fills und Spur-Effekten unter `songs/` (*Eigenen Song laden*).

## Kits

| Kit | Herkunft | Lizenz |
|---|---|---|
| BlackPearl | [AVL Drumkits](http://www.bandshed.net/avldrumkits/), im Repo | CC BY-SA 3.0 |
| CrocellKit | [DrumGizmo](https://drumgizmo.org/wiki/doku.php?id=kits%3Acrocellkit), Stereo-Mix von Henry Järvinen | CC BY 4.0 |
| VirtuosityDrums | [Versilian Studios / Karoryfer](https://github.com/sfzinstruments/virtuosity_drums) | CC0 |
| 808 / 909 (Synth) | synthetisiert | – |

CrocellKit und VirtuosityDrums sind zu groß fürs Repo und werden einmalig gebaut:

```bash
julia --project=. tools/build_crocell.jl       # lädt 561 MB
julia --project=. tools/build_virtuosity.jl    # lädt 1,2 GB
```

## Lizenz

Code: [MIT](LICENSE). Die Samples stehen unter den oben genannten Lizenzen.
