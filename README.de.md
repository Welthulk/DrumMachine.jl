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

2. **DrumMachine aus dem Julia-Paketregister installieren** (sobald die Registrierung durch ist):

   ```bash
   julia -t auto -e 'using Pkg; Pkg.add("DrumMachine"); using DrumMachine; DrumMachine.run()'
   ```

   Eigene Songs und WAV-Exporte liegen dann in `~/.local/share/DrumMachine/songs`.

   **Oder** Repo holen und Pakete installieren (dauert beim ersten Mal einige Minuten):

   ```bash
   git clone https://github.com/Welthulk/DrumMachine.jl.git
   cd DrumMachine.jl
   julia --project=. -e 'using Pkg; Pkg.instantiate()'
   ```

3. **Empfohlene Systemprogramme** (Debian/Ubuntu):

   ```bash
   sudo apt install libarchive-tools zenity ffmpeg
   ```

   - `libarchive-tools` (bsdtar) entpackt beim ersten Start die großen Sample-Kits
     (Alternativen: `unrar` und `unzip`)
   - `zenity` (GNOME) oder `kdialog` (KDE) für die Datei-Dialoge
   - `ffmpeg` nur für den AAC-Export im WAV-Editor

## Start

```bash
./start_drum.sh
# oder: julia -t auto --project=. run.jl
```

Wichtig: aus einem normalen Terminal starten. In Umgebungen ohne OpenGL (z. B. VS Code als
Flatpak) öffnet sich kein Fenster.

Schneller Start: Fehlt das Sysimage `build/drummachine.so` (vorkompiliertes GLMakie), fragt
`./start_drum.sh`, ob es jetzt gebaut werden soll (dauert einige Minuten). Danach meldet das
Skript bei jedem Start, ob es das Image gefunden hat, und fragt nach Paket-Updates von selbst
nach einem Neubau. Direkt bauen: `./start_drum.sh --build`.

**Sprache:** Deutsch oder Englisch über *DE* / *EN* in der Kopfzeile. Voreingestellt ist die
Systemsprache, die Wahl wird in `~/.config/DrumMachine/settings.toml` gespeichert.

**Kits beim ersten Start:** CrocellKit (561 MB) und VirtuosityDrums (1,2 GB) sind zu groß fürs
Repo. Beim ersten Start werden sie automatisch im Hintergrund geladen und gebaut, der Fortschritt
steht in der Statuszeile. BlackPearl und die Synth-Kits gehen sofort, die neuen Kits erscheinen
im Kit-Menü, sobald sie fertig sind. Ablage: `~/.local/share/DrumMachine/kits`, die Downloads in
`~/.cache/DrumMachine` (danach löschbar). Abschalten mit `auto_kits = false` in der
Einstellungsdatei oder der Umgebungsvariable `DRUMMACHINE_NO_KIT_DOWNLOAD`.

**Loop-Export:** Schalter *Loop* in der Export-Zeile. Die WAV hat dann keinen Einzähler, ist exakt
ganze Takte lang, und das Ausklingen wird auf den Anfang gefaltet. So läuft sie ohne Lücke in
Schleife. Am Roland TD-27: SONG → [F2] SETUP → Loop Type = LOOP.

**Song-Dateien:** einfache TOML-Dateien, auch von Hand editierbar. Alle Felder inklusive Master- und
Spur-Effekten beschreibt [docs/song-format.md](docs/song-format.md) (englisch).

**Metronom:** Knopf *Metronom* in der Kopfzeile. 30–400 BPM per Regler, Eingabe oder Tap,
Taktarten bis 12/8 mit Akzentgruppen, Unterteilung (Achtel, Triolen, 16tel, Swing, punktiert …),
Betonung (Akzent auf der 1, ohne, nur 2 und 4, nur Offbeats), sieben Klänge, Lücken-Training
(n Takte spielen, m Takte stumm) und Tempo-Trainer (+x BPM alle n Takte). Die Einstellungen
werden gespeichert.

**WAV-Editor:** Knopf *WAV-Editor* in der Kopfzeile. Exportierte WAVs schneiden, trimmen, Fades,
Normalisieren, Gain, Effekte und EQ, Einzähler voranstellen, BPM erkennen, mit Rückgängig. Unter
*Format* gibt es auch AAC (.m4a), z. B. zum Verschicken per WhatsApp (braucht ffmpeg).

![WAV-Editor](docs/wav-editor.png)
 Siehe
[docs/wav-editor.md](docs/wav-editor.md) (englisch) oder den Knopf *Docs* im Programm.

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

Manueller Neubau: `julia --project=. tools/build_crocell.jl` bzw. `tools/build_virtuosity.jl`.

## Lizenz

Code: [MIT](LICENSE). Die Samples stehen unter den oben genannten Lizenzen.
