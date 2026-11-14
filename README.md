# DrumMachine.jl

Step-Sequencer in Julia zum Schlagzeug-Üben: Groove eintragen, vorhören und als WAV exportieren,
zum Beispiel um ihn auf dem Drumcomputer abzuspielen und mitzuspielen.

## Start

```bash
cd ~/DrumMachine
julia -t auto --project=. run.jl
```

`-t auto` ist wichtig, denn das Audio läuft in einem eigenen Thread.
Die Live-Wiedergabe puffert 150 ms, damit Pausen der Garbage Collection nicht hörbar werden.
Der WAV-Export ist davon unabhängig und sample-genau.
GLMakie braucht ein echtes Grafik-Display. Starte das Programm daher aus einem normalen Terminal,
nicht aus dem Terminal der Flatpak-Version von VS Code.

In der REPL:

```julia
using DrumMachine
fig, eng = DrumMachine.run(block = false)
```

## Bedienung

| Aktion | Wie |
|---|---|
| Schlag setzen/löschen | Linksklick ins Raster (normaler Schlag) |
| Dynamik | Rechtsklick: Ghost → normal → Akzent |
| Vorhören | Klick auf den Spurnamen |
| Play/Stop | Button oder Leertaste |
| Pattern-Modus | spielt das gerade angezeigte Pattern in Schleife |
| Song-Modus | spielt die **Kette** in Schleife |
| Kette | z. B. `1 1 1 2` oder `1x3 2` (3× Groove, 1× Fill) |
| Raster | 16tel, Triolen (Shuffle/Jazz/12/8), 16tel-Triolen (Half-Time Shuffle) oder 8tel; die Kopfzeile zählt mit (`1 e + a`, `1 + a`, `1 la li + la li`) |
| Swing | Lage der Off-Beat-Note im Schlag: 50 % = gerade, 67 % = Triole, 75 % = punktiert. Im Triolen-Raster verschiebt der Regler die dritte Triole (Standard 67 %). Im geraden Raster ist die Basis wählbar: **Auto** (16tel-Swing, wenn Schläge auf „e“/„a“ liegen, sonst 8tel), **auf 8tel** oder **auf 16tel**. Swing wird mit dem Song gespeichert |
| M / S | Spur stumm / solo; **Mute gilt auch beim Export** |
| Neu | leerer Groove mit freiem Namen (BPM, Raster und Kit bleiben) |
| Duplizieren | Kopie des aktuellen Songs („… Kopie“), das Original bleibt unangetastet |
| Speichern | schreibt `songs/<Name>.toml`. Existiert die Datei schon, fragt der Button erst „Überschreiben?“, ein zweiter Klick bestätigt |
| Preset laden … | Groove aus der Bibliothek (siehe unten) |
| Eigenen Song laden … | alle gespeicherten Songs aus `songs/` |

## Groove-Bibliothek

Über **Preset laden …** stehen diese Grooves bereit. Die Blues-Presets sind als 12-Takt-Form
mit Crash am Anfang und Fill im letzten Takt angelegt.

| Stil | Presets |
|---|---|
| Rock / Pop | 8tel (mit Crash & Fill), 16tel, Half-Time, Punk, Rock'n'Roll, Ballade (mit Fill), Motown, Disco |
| Country | Train Beat |
| Funk | Ghost Notes, Oakland (Tower-of-Power-Stil, mit Variation), Linear, 16tel Zwei-Hand-Hihat |
| Shuffle | Rock-Shuffle (mit Crash & Fill), Ride-Shuffle, Snare-Shuffle (Chicago), Half-Time (8tel-Triolen), Purdie Half-Time (16tel-Triolen), Rosanna-Stil (Porcaro/Purdie), Laid-back 58 %, Hart punktiert 75 %, 8tel-Swing im geraden Raster, 16tel-Swing |
| Blues | Shuffle (12 Takte), Double Shuffle (Texas), Slow Blues 12/8, Jump / Swing |
| Jazz | Swing Ride, Jazz-Walzer 3/4 |
| Latin / Reggae | Bossa Nova, Samba, Afro 6/8, One Drop, Rockers |
| Hip-Hop / R&B | Boom Bap, Neo Soul |
| Taktarten | Walzer 3/4, 6/8 Ballade, 5/4, 7/8 (2+2+3) |

Eigene Grooves kommen in [src/presets.jl](src/presets.jl) dazu, oder du speicherst sie einfach als Song.

## WAV-Export zum Üben

Unten in der Zeile **Export**:

- **Wiederholungen**: so oft wird die Kette hintereinander geschrieben.
- **Einzähler**: 0–4 Takte Klick vor dem Groove.
- **Klick**: legt ein Metronom auf jeden Schlag.
- **Stereo | Mono**: Schalter zwischen Stereo und Mono. Wirkt sofort auf die Wiedergabe (damit du hörst,
  was exportiert wird) und schreibt bei Mono eine einkanalige WAV. Wird mit dem Song gespeichert.

Die Datei landet in `songs/<Name>.wav` (44,1 kHz, 16 Bit PCM). Rechts neben dem Button
steht die zu erwartende Länge.

Tipp: Mit **M** kannst du einzelne Instrumente stummschalten, zum Beispiel die Snare,
und dann genau den Part selbst spielen.

## Speichern & Grooves als Text

Songs werden als TOML in `songs/` gespeichert und lassen sich von Hand bearbeiten:

```toml
bpm = 92.0
steps_per_beat = 4
chain = [1, 1, 1, 2]

[[pattern]]
steps = 16
    [pattern.rows]
    HiHat = "x.x.x.x.x.x.x.x."
    Snare = "....X..o.o..X..o"
    Kick  = "X.x.......X..x.."
```

`.` = aus, `o` = Ghost, `x` = normal, `X` = Akzent.
Spuren: `Kick Snare Rim HiHat HHOpen HHPedal Tom FloorTom Ride RideBell Crash`.

Ohne GUI geht es auch per Skript:

```julia
using DrumMachine
kit  = first(available_kits())          # BlackPearl
song = load_song("songs/MeinGroove.toml")
song.bpm = 80
export_wav("songs/MeinGroove_80.wav", song, kit; repeats = 16, countin = 2, click = true)
```

## Kits

- **BlackPearl** (`kits/BlackPearl/`): akustisches Kit der *AVL Drumkits* von Glen MacArthur,
  CC BY-SA 3.0, siehe [kits/BlackPearl/LICENSE.txt](kits/BlackPearl/LICENSE.txt).
  Jeder Sound hat 5 Velocity-Layer. Ghost, normal und Akzent nutzen dabei unterschiedliche
  Aufnahmen und wechseln per Round-Robin.
- **Synth**: vollständig synthetisch und dient als Ersatz, wenn Samples fehlen.

Ein eigenes Kit legst du als Ordner `kits/<Name>/` an, mit WAV-Dateien und einer `kit.toml`
(Vorlage: `kits/BlackPearl/kit.toml`). Erwartet wird `<file>-1.wav … <file>-5.wav` (leise → laut)
oder eine einzelne `<file>.wav`.

## Tests

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```
