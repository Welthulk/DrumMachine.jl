# DrumMachine.jl

Step-Sequencer in Julia zum Schlagzeug-Üben: Groove eintragen, vorhören und als WAV exportieren,
zum Beispiel um ihn auf dem Drumcomputer abzuspielen und mitzuspielen.

## Start

```bash
cd ~/DrumMachine
julia -t auto --project=. run.jl
```

`-t auto` ist wichtig, denn das Audio läuft in einem eigenen Thread.
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
| Raster | 16tel, Triolen (Shuffle/Jazz/12/8) oder 8tel; die Kopfzeile zählt `1 e + a` bzw. `1 + a` |
| Swing | 50 % = gerade, 66 % ≈ triolisch (wirkt bei 16tel/8tel) |
| M / S | Spur stumm / solo; **Mute gilt auch beim Export** |

## WAV-Export zum Üben

Unten in der Zeile **Export**:

- **Wiederholungen**: so oft wird die Kette hintereinander geschrieben.
- **Einzähler**: 0–4 Takte Klick vor dem Groove.
- **Klick**: legt ein Metronom auf jeden Schlag.
- **Mono**: falls der Drumcomputer nur Mono-Samples nimmt.

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
