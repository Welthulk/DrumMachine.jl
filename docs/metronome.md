# Metronome

The metronome (button *Metronom* in the header) opens in its own window. It plays through the same
audio output as the drum machine but independently of the song: it can run alone or alongside a
playing groove (the two are not synchronized). Closing the window stops it. All settings are saved
and come back the next time the window is opened.

## Display

- The large number is the current tempo in BPM (quarter notes per minute).
- One dot per pulse of the bar. Larger dots with an orange ring mark the start of an accent group,
  the largest one is the one. The dot of the pulse being heard lights up.
- Below: the bar number, *stumm – weiterzählen!* (silent – keep counting) in a muted bar of the
  gap training, and the target tempo while the tempo trainer is active.

## Tempo

| Control | Effect |
|---|---|
| *▶ Start* / *■ Stop* | start on the one / stop (also the space bar) |
| slider | 30–400 BPM |
| −5 −1 +1 +5 | change the tempo in steps (↑ / ↓ keys: ±1) |
| field | type a tempo and press Enter or click elsewhere; decimals are rounded, a comma works too |
| *Tap* | tap at least twice in the tempo (also the T key); the average of the last taps is used, a pause of more than 2 s starts over |
| *Song-Tempo* | takes over the tempo of the song in the main window |

Tempo changes take effect immediately, all other settings at the start of the next bar.

## Time signature

*Taktart* (time signature): 1/4 to 7/4 and 3/8 to 12/8. The BPM always count quarter notes; in
x/8 time signatures each pulse is an eighth note, so 6/8 at 60 BPM has six eighths at 120 per
minute.

Time signatures with groups are accented accordingly, for example 7/8 (2+2+3) or 7/8 (3+2+2),
5/4 (3+2) or 5/4 (2+3), 6/8 (3+3), 12/8 (3+3+3+3).

## Subdivision

*Unterteilung* (subdivision) adds softer clicks between the pulses:

| Setting | Clicks per pulse |
|---|---|
| *keine* | none |
| *2 pro Schlag (Achtel)* | 2, eighths in x/4 |
| *3 pro Schlag (Triolen)* | 3, triplets |
| *4 pro Schlag (16tel)* | 4, sixteenths in x/4 |
| *5 pro Schlag* | 5, quintuplets |
| *6 pro Schlag (Sextolen)* | 6, sextuplets |
| *Swing (1. + 3. Triole)* | 1st and 3rd triplet, the swing feel |
| *Punktiert (1. + 4. 16tel)* | 1st and 4th sixteenth, dotted eighth + sixteenth |

*Unterteilung leiser/lauter* sets the level of these clicks relative to the pulses.

## Accents

*Betonung* (accents) decides which pulses sound:

| Setting | Effect |
|---|---|
| *Akzent auf der 1* | accent on the one, group starts slightly accented, subdivision on |
| *Ohne Akzent* | all pulses equal, subdivision on |
| *Nur 2 und 4* | only the even pulses, as for swing and backbeat practice |
| *Nur Offbeats (+)* | only the "and" between the pulses |
| *Nur die 1* | only the first pulse of each bar |

The subdivision only sounds with the first two settings.

## Sound

*Klang* (sound): *Klick*, *Beep*, *Woodblock*, *Cowbell*, *Claves*, *Sticks* (synthesized), or
instruments of the kit selected in the main window: *Kit: Side Stick*, *Kit: Ride* (accent on the
ride bell) and *Kit: Hi-Hat*. The kit sounds follow a kit change in the main window.

*Lautstärke* (volume) sets the overall level of the metronome.

## Gap training

*Lücken-Training: spielen* n *Takte, stumm* m *Takte* (gap training: play n bars, mute m bars):
the metronome plays n bars and then stays silent for m bars, over and over. Keep the time during
the silent bars; if you are still on the one when the click returns, the tempo held. 0 silent bars
switches it off. Choosing silent bars while the play count is 0 sets it to 4.

## Tempo trainer

*Tempo-Trainer: +* x *BPM alle* n *Takte bis* max *BPM*: after every n bars the tempo rises by x
BPM until the maximum is reached; then it stays there. *0* switches it off. The slider and the
display follow the rising tempo, stopping keeps the reached tempo.

## Keys

| Key | Effect |
|---|---|
| space | start / stop |
| ↑ / ↓ | tempo ±1 |
| T | tap tempo |

The keys work while no input field in the metronome window is being edited.

## Delay

The click is heard after the audio buffer (`audio_latency`, 0.08 s by default, see the README).
The display is delayed by the same amount so that the lit dot matches what is heard.
