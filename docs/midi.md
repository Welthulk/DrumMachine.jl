# MIDI recording and export

Hits from an electronic drum kit can be recorded straight into the patterns. The kit is connected
by USB; a separate MIDI interface is not needed. The controls are in the third row of the
transport panel: *● Aufnahme* (record), the *MIDI* input menu, *↻* (search again) and
*Mithören* (monitor).

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

- **Stopped:** *● Aufnahme* plays the pattern shown in the grid in a loop, after one count-in bar.
- **Playing:** recording starts at once, in pattern mode as well as in song mode. In song mode the
  hits go into the pattern of the chain that is playing; the grid follows it.
- **Stop** (button or space bar) ends the recording. *● Aufnahme* again stops recording but keeps
  playing.

How a hit is placed:

- It goes to the nearest step of the pattern that was playing when you played it. The real step
  times count: swing, the pattern's own tempo and the grid (16ths, triplets, 32nds).
- A hit just before the end of the bar that rounds past the last step goes to step 1 of the next
  bar played. In pattern mode that is step 1 of the same pattern.
- In the count-in bar only an early hit on the one of the first real bar counts, everything else
  is ignored.
- Overdub: hits are added to what is there. If the step already has a hit on that track, the
  louder of the two stays. Nothing is deleted.
- Velocity sets the level: below `midi_ghost` (45) a ghost note, from `midi_accent` (105) on an
  accent, normal in between.
- The status line shows where the hit went and how far it was from the step, e.g.
  `→ Pattern 1, Step 5 (+12 ms)`.

There is no undo. To keep a pattern as it is, make a copy first (*+ Kopie*) and record into the
copy; *Leeren* clears a pattern.

*Mithören* (monitor) also plays the kit sound of each hit through DrumMachine. It comes later by
the audio buffer (about 90 ms with the default settings), so it is meant for checking the mapping.
For playing, use the module's own sound.

## Note table

Factory note numbers of the TD-27 and the track they go to. Heads, rims and edges of a pad go to
the same track, except the snare cross stick.

| Pad | Notes | Track |
|---|---|---|
| Kick | 36 | Kick |
| Snare head, rim | 38, 40 | Snare |
| Snare cross stick | 37 | Side Stick |
| Tom 1 head, rim | 48, 50 | Tom |
| Tom 2 head, rim | 45, 47 | Tom |
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
`HHOpen`, `HHPedal`, `Tom`, `FloorTom`, `Ride`, `RideBell`, `Crash`. Any other value (e.g. `"off"`)
removes the note.

## Settings

In `~/.config/DrumMachine/settings.toml`:

```toml
midi_device = "TD-27 MIDI 1"     # example; the name as shown in the MIDI menu, set by the menu
midi_ghost = 45                  # velocity below this: ghost note
midi_accent = 105                # velocity from this on: accent
midi_offset_ms = 0               # timing correction in ms, positive = hits count earlier

[midi_map]
"40" = "Rim"                     # snare rim as side stick
"60" = "Crash"                   # an extra pad on note 60
"26" = "off"                     # ignore the open hi-hat edge
```

Top-level keys have to come before `[midi_map]` (and before the other tables in the file).
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

## MIDI file export

The *MIDI* button next to *WAV exportieren* writes the song as `<name>.mid` into the song folder
(`songs/`, or `~/.local/share/DrumMachine/songs` for an installed package): a Standard MIDI
File (format 0, 960 ticks per quarter note, channel 10) for a DAW, for MuseScore (drum notation) or
for another drum machine. It uses the same settings as the WAV export: chain, repeats, count-in,
click and *Loop* (no count-in).

- Notes as in the note table, one per track: Kick 36, Snare 38, Side Stick 37, HiHat 42, HH offen
  46, HH Pedal 44, Tom 48, Floor Tom 43, Ride 51, Ride Bell 53, Crash 49. Click 33, beat 1 34.
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
