"""
    DrumMachine

Step sequencer for drum practice: enter a groove, preview it, export it as WAV.

    using DrumMachine
    DrumMachine.run()                 # start the GUI
    song = preset("Rock: 8tel")
    export_wav("rock.wav", song, first(available_kits()))
"""
module DrumMachine

include("i18n.jl")
include("lang/en_core.jl")
include("lang/en_gui.jl")
include("lang/en_wavedit.jl")
include("lang/en_aac.jl")
include("dsp.jl")
include("kit.jl")
include("kitbuild.jl")
include("analog.jl")
include("song.jl")
include("presets.jl")
include("fill.jl")
include("wavedit.jl")
include("aac.jl")
include("engine.jl")
include("gui.jl")
include("docs_view.jl")
include("wavedit_gui.jl")

export Song, Pattern, TrackParams, Kit, Engine,
       preset, PRESET_NAMES, pattern_from_rows, row_string, parse_chain,
       save_song, load_song, load_kit, synth_kit, available_kits,
       render_song, export_wav, ascii_filename, song_seconds,
       make_fill, FILL_STYLES,
       Wave, load_wave, save_wave

end
