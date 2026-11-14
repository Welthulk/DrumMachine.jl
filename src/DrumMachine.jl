"""
    DrumMachine

Step-Sequencer zum Schlagzeug-Üben: Groove eintragen, vorhören, als WAV exportieren.

    using DrumMachine
    DrumMachine.run()                 # GUI starten
    song = preset("Rock: 8tel")
    export_wav("rock.wav", song, first(available_kits()))
"""
module DrumMachine

include("dsp.jl")
include("kit.jl")
include("song.jl")
include("presets.jl")
include("engine.jl")
include("gui.jl")

export Song, Pattern, TrackParams, Kit, Engine,
       preset, PRESET_NAMES, pattern_from_rows, row_string, parse_chain,
       save_song, load_song, load_kit, synth_kit, available_kits,
       render_song, export_wav, song_seconds, run

end
