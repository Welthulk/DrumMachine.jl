# MIDI recording, output and export

Hits from an electronic drum kit can be recorded straight into the patterns. The kit is connected
by USB; a separate MIDI interface is not needed. The controls are in the third row of the
transport panel: *● Aufnahme* (record), the *MIDI* input menu, *↻* (search again) and
*Mithören* (monitor). The same row has the MIDI output (*Ausgang*, *Pegel*): the module plays
your patterns and songs with its own sounds, see *Playing through the module* below.

The defaults are made for a Roland TD-27. Other modules work too if they send note-on messages;
their notes may need a mapping (see *Note table* below).

## Connecting the TD-27

1. Connect the TD-27 to the computer with a USB cable (USB B port on the module).
2. On Linux the module must be in USB driver mode **GENERIC** (VENDOR mode needs Roland's own
   driver). On the module: *SETUP*, then the USB / system
   settings, *Driver Mode* = *GENERIC*. Then switch the module off and on again.
3. Check that the system sees it: `aconnect -l` (package `alsa-utils`) lists a client with *TD-27*
   in its name, or open the *MIDI* menu in DrumMachine.

Windows and macOS are untested.

## Choosing the input

The *MIDI* menu lists all MIDI inputs (*aus* = off). While no input is open, the list is read
again whenever the menu opens, so a module switched on later appears there. With an input open,
press *↻* to search again. *↻* searches again, reopens the chosen input
and reads the MIDI settings from `settings.toml` again (after editing them). If the module was
switched off and on or replugged while its input was open, press *↻* (or choose *aus* and then
the input again). Choosing the input that is already open does nothing.

The choice is saved as `midi_device` and opened again at the next start. If the device is missing
then, the program starts as usual and says so in the status line.

Every hit shows up in the status line: track, note number and velocity. Notes without a track are
shown with their number, so you can add them to `[midi_map]`.

## Recording

*● Aufnahme* records into a new song, bar by bar:

1. Choose the MIDI input and press *● Aufnahme*. The recording window opens with tempo (BPM,
   slider or field), grid (16ths, triplets, 8ths, 32nds), bar length (2/4 to 7/4), preset from the
   current song, and the length of the recording: free (until a pause) or 2 to 32 bars.
2. Press *Start* in the window. Your song is put aside, a click plays in that tempo (accent on
   the one), and the window shows in large letters *Warte auf den ersten Schlag …*. Take your
   time to get to the kit; nothing is recorded before your first hit (after 3 minutes without
   a hit the recording stops).
3. From your first hit on every bar is recorded: the window shows the bar number and the bar
   being played as a small grid, the main button shows *■ Takt n*.
4. With a fixed length the recording ends after that many bars; free, it ends after 8 seconds
   without a hit. *Stop* in the window or the main window (or the space bar) ends it too.
5. The recording is loaded right away as a new song named *Aufnahme <date time>*; your previous
   song is backed up first to `~/.local/state/DrumMachine/vor_aufnahme.toml` (overwritten each
   time). Play it, then keep it with *Speichern*. The result window shows all bars at a glance
   with their pattern number and the chain; *Rückgängig* there brings your previous song back.
6. *● Aufnahme* again (the window stays open) starts the next take with the same settings.

How the hits become a song:

- Tempo and grid stay fixed during the recording, without swing, so every hit goes to the nearest
  step of the bar it falls into, counted from the start of the click. A hit just before a bar line
  goes to step 1 of the next bar.
- The song runs from the bar of your first hit to the bar of your last. Every bar becomes a chain
  entry; equal bars share one pattern, so a steady groove gives few patterns (e.g. chain
  `1 2 2 2 1 2 2 2`). At most 24 different patterns: beyond that a bar takes the most similar
  pattern (the result window says how many).
- Two hits of a track on one step keep the louder level.
- Velocity sets the level: below `midi_ghost` (45) a ghost note, from `midi_accent` (105) on an
  accent, normal in between. Each track can have its own thresholds (`[midi_levels]`, set by
  *Einmessen*).
- The status line shows each hit with bar, step and its distance from the step, e.g.
  `→ Takt 3, Step 5 (+12 ms)`.

*Mithören* (monitor) also plays the kit sound of each hit through DrumMachine. It comes later by
the audio buffer (about 90 ms with the default settings), so it is meant for checking the mapping.
For playing, use the module's own sound.

## Einmessen (calibration)

Pads respond differently, and so does every player: on the TD-27 a hi-hat accent on the edge may
come at velocity 70 to 127 while a soft stroke on the bow comes at 30 to 60, and a snare backbeat
at 50 to 80. One pair of thresholds for all pads does not fit that. *Einmessen* sets them per
track from your playing:

1. Choose the MIDI input and press *Einmessen*. Your song is put aside and the pattern
   *Einmessen* plays in a loop at 80 BPM after one count-in bar:

   ```
            1 e + a 2 e + a 3 e + a 4 e + a
   HiHat    X . x . X . x . X . x . X . x .
   Snare    . . . . x . o . . . . . x . o .
   Kick     x . . . . . . . x . . . . . . .
   ```

   A window opens with large letters, readable from the drum kit. It shows the phase, the last
   32 hits per track (velocity, colored by the level in the grid) with the current thresholds,
   and the typical timing. The button in the main window turns red and shows the phase too.
2. **Waiting:** nothing is measured until your first hit. Take your time to get to the kit and
   put on the headphones (the pattern plays on; after 3 minutes without a hit it stops).
3. **Warm-up:** the first 8 bars after your first hit (24 s at 80 BPM) are not measured, so you
   can settle into the groove. The window counts down.
4. **Measuring:** play loud and soft as written (hi-hat loud on the beats, soft in between;
   snare backbeat normal, ghost note on the "and" after it). Stop playing for 6 seconds and the
   measurement ends by itself; Stop in the main window ends it as well.
5. **Result:** your song comes back as it was, unsaved changes included (saving is blocked while
   calibrating), and a result window opens. Per track it shows each measured hit along the
   velocity axis in rows ghost, normal and accent, the new thresholds (solid) and the old ones
   (dashed), hits that would get another level in red, and how many hits are recognized with the
   new and the old thresholds. Below, a histogram of the timing. *Übernehmen* saves the
   thresholds in `[midi_levels]` and the timing in `midi_offset_ms`; *Verwerfen* or closing
   the window changes nothing.

How the thresholds are found:

- Each hit is compared with the level written in its cell. Hits in empty cells, during the
  warm-up or more than 50 ms off the typical timing do not count.
- Closed and open hi-hat are one cymbal: a module sends "open" when the pedal is not quite closed,
  so such hits count where the pattern has a hi-hat, and both hi-hat tracks get the same
  thresholds.
- Only tracks with at least 8 hits are changed. A boundary between two levels needs at least 3
  hits of each; it is set where the fewest hits land on the wrong side.
- If a level was not played (e.g. no accent on the kick), its threshold moves only as far as
  needed so that 98 % of the hits played keep their level.

Timing: the median distance of the measured hits from their steps (positive = after the beat)
is added to `midi_offset_ms` when it is at least 3 ms and at least 16 hits were measured. It
covers what the latency compensation does not know (USB, sound server) and your own habit of
playing ahead of or behind the beat, so recorded hits land on the step you meant.

Run it again after changing the trigger settings of the module. Tracks not in the pattern
(toms, cymbals) keep their thresholds; set them by hand in `[midi_levels]` if needed.

## Note table

Factory note numbers of the TD-27 and the track they go to. Heads, rims and edges of a pad go to
the same track, except the snare cross stick.

| Pad | Notes | Track |
|---|---|---|
| Kick | 36 | Kick |
| Snare head, rim | 38, 40 | Snare |
| Snare cross stick | 37 | Side Stick |
| Tom 1 head, rim | 48, 50 | Tom 1 |
| Tom 2 head, rim | 45, 47 | Tom 2 |
| Tom 3 head, rim | 43, 58 | Floor Tom |
| Hi-hat open bow, edge | 46, 26 | HH offen |
| Hi-hat closed bow, edge | 42, 22 | HiHat |
| Hi-hat pedal | 44 | HH Pedal |
| Crash 1 bow, edge | 49, 55 | Crash |
| Crash 2 bow, edge | 57, 52 | Crash |
| Ride bow, edge | 51, 59 | Ride |
| Ride bell | 53 | Ride Bell |

General MIDI notes as fallback for other modules: 35 Kick, 39 Snare, 41 Floor Tom. Other notes are
ignored.

Own assignments go into the table `[midi_map]` of the settings file, note number as key, track id as
value. They replace the entries above for those notes. Track ids: `Kick`, `Snare`, `Rim`, `HiHat`,
`HHOpen`, `HHPedal`, `Tom`, `Tom2`, `FloorTom`, `Ride`, `RideBell`, `Crash`. Any other value (e.g. `"off"`)
removes the note.

## Settings

In `~/.config/DrumMachine/settings.toml`:

```toml
midi_device = "TD-27 MIDI 1"     # example; the name as shown in the MIDI menu, set by the menu
midi_ghost = 45                  # velocity below this: ghost note
midi_accent = 105                # velocity from this on: accent
midi_offset_ms = 0               # timing correction in ms, positive = hits count earlier
midi_out_device = "TD-27 MIDI 1" # MIDI output of the main window, set by the menu Ausgang
midi_out_level = 100             # velocity of the notes sent in %, set by the slider Pegel

[midi_levels]                    # per track: [ghost below, accent from]; set by Einmessen
HiHat = [36, 66]

[midi_map]
"40" = "Rim"                     # snare rim as side stick
"60" = "Crash"                   # an extra pad on note 60
"26" = "off"                     # ignore the open hi-hat edge
```

Top-level keys have to come before `[midi_levels]` and `[midi_map]` (and before the other tables in the file).
Changes take effect at the next start or after *↻*.

## Latency

You play to what you hear, and that comes later than the program computes it: by the audio buffer
(`audio_latency`, 0.08 s by default, as reported by the sound system) plus one block of 512
samples (12 ms). DrumMachine subtracts this from every hit, so a hit on the beat you hear lands on
that step.

If hits land too late or too early by the same amount, correct it with `midi_offset_ms`: look at
the ms values in the status line while recording quarter notes with the click. If most of them
show about `+15 ms`, set `midi_offset_ms = 15`; for `-10 ms` set `-10`.

A smaller `audio_latency` makes playing along easier, as long as there are no dropouts (see the
README, *Against crackles and dropouts*).

## Playing through the module

The *Ausgang* menu lists the MIDI outputs (*aus* = off). With an output chosen, *Play* sends the
pattern (pattern mode, in a loop) or the chain (song mode, in a loop) to the module instead of
playing the kit, so you hear it in the headphones of the module and can play along.

- Channel 10, notes as in the MIDI file export (Kick 36, Snare 38, … Crash 49), controller 4
  before each hi-hat note. Ghost note, normal and accent get velocity 35, 90 and 120, scaled by
  the track volume, ornaments and *Human*. Each note ends after 30 ms (drum modules ignore that).
- Mute and solo work as usual. Count-in and click of DrumMachine still come from the sound card.
- *Pegel* (10 to 100 %) scales the velocity of all notes sent. The TD-27 does not take MIDI
  volume (controller 7), so this is the way to make the playback quieter than your own playing.
  Lower velocities also pick softer samples on the module.
- MIDI clock: on *Play* the output gets a Start, then 24 clock ticks per beat in the tempo of the
  pattern (swing does not move the beats), and a Stop at the end. The click of the TD-27 follows
  it when *SYSTEM → MIDI → SYNC*, *Sync Mode* is set to *EXTERNAL*; switch the click on at the
  module and set its volume there. The time signature of that click is set at the module.
- The notes are timed for the moment the sound card plays the same point, so the module and
  DrumMachine (click, other windows) stay in time.
- Your own hits through the MIDI input are not sent back to the module. With *Mithören* on they
  also play the kit sound of DrumMachine.
- The choice is saved as `midi_out_device` and opened again at the next start; the level is
  saved as `midi_out_level`. The setup player can use the same output at the same time.
- If the module stops answering (unplugged), the status line says so. Choose *aus* and the
  output again after plugging it back in.

## MIDI file export

The *MIDI* button next to *WAV exportieren* writes the song as `<name>.mid` into the song folder
(`songs/`, or `~/.local/share/DrumMachine/songs` for an installed package): a Standard MIDI
File (format 0, 960 ticks per quarter note, channel 10) for a DAW, for MuseScore (drum notation) or
for another drum machine. It uses the same settings as the WAV export: chain, repeats, count-in,
click and *Loop* (no count-in).

- Notes as in the note table, one per track: Kick 36, Snare 38, Side Stick 37, HiHat 42, HH offen
  46, HH Pedal 44, Tom 1 48, Tom 2 45, Floor Tom 43, Ride 51, Ride Bell 53, Crash 49. Click 33, beat 1 34.
- Ghost note, normal and accent get velocity 35, 90 and 120.
- Before each hi-hat note, controller 4 (hi-hat opening) is set on channel 10 at the same tick:
  127 (closed) for HiHat 42 and HH Pedal 44, 0 (open) for HH offen 46. Roland modules such as the
  TD-27 use controller 4 for the hi-hat opening, so they play the hi-hat sounds as written.
- Swing, the tempo of each pattern (as tempo changes) and the time signature from the steps are in
  the file. Double strokes, buzz rolls, flams and drags are written out as single notes.
- Triplet bars get a signature in 8ths when they fill whole 8ths, e.g. 9 steps at 6 steps per beat
  as 3/8. A triplet bar that is not a whole number of 8ths (e.g. 10 or 16 steps at 3 steps per
  beat) has no exact time signature. The previous one stays in effect, so from that bar on the bar
  lines in a DAW are shifted; the status line warns about it. Pad such patterns to whole beats.
- A flam or drag on step 1 without count-in gets a pickup bar of a 16th before bar 1 (longer for
  a long flam or drag at a fast tempo). The WAV export starts with the same pickup, so both files
  line up at time 0.
  In a *Loop* export its grace notes are at the end of the file, as in the loop WAV.
- Muted tracks are left out, as in the WAV export.

From a script: `export_midi("groove.mid", song)`.

The setup player plays MIDI files through a MIDI output, e.g. to the TD-27: see *MIDI files* in
the setup player documentation.
