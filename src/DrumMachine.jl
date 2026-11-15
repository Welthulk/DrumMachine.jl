"""
    DrumMachine

Step sequencer for drum practice: enter a groove, preview it, export it as WAV.

    using DrumMachine
    DrumMachine.run()                 # start the GUI
    song = preset("Rock: 8tel")
    export_wav("rock.wav", song, first(available_kits()))
"""
module DrumMachine

include("dsp.jl")
include("kit.jl")
include("analog.jl")
include("song.jl")
include("presets.jl")
include("fill.jl")
include("engine.jl")
include("gui.jl")

export Song, Pattern, TrackParams, Kit, Engine,
       preset, PRESET_NAMES, pattern_from_rows, row_string, parse_chain,
       save_song, load_song, load_kit, synth_kit, available_kits,
       render_song, export_wav, ascii_filename, song_seconds,
       make_fill, FILL_STYLES

end
