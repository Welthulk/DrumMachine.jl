# Precompile workload: the methods of a typical start (presets, kit, rendering, building the
# window without displaying it) are compiled when the package is installed instead of at every
# start. Uses only the BlackPearl kit shipped with the package, no audio, no window.
using PrecompileTools: @setup_workload, @compile_workload

@setup_workload begin
    pearl = KitEntry("BlackPearl", joinpath(KIT_DIR, "BlackPearl"))
    @compile_workload begin
        song = preset("Rock: 8tel")
        foreach(preset, PRESET_NAMES)
        kit = isfile(joinpath(pearl.src, "kit.toml")) ? get_kit(pearl) : kit_808()
        render_song(song, kit; repeats = 1, countin = 1)
        make_fill(song.patterns[2], song.steps_per_beat, 2)
        mktempdir() do dir
            export_wav(joinpath(dir, "t.wav"), song, kit; repeats = 1)
            save_song(joinpath(dir, "t.toml"), song)
            load_song(joinpath(dir, "t.toml"))
        end
        kit_entries()
        try
            _, eng, _ = build_gui(song; audio = false)
            build_gui(song; audio = false, eng)                 # rebuild on language switch
            with_theme(() -> metronome_figure(Engine(song, kit)), DM_THEME)
        catch e
            @debug "precompile: build_gui failed" exception = e
        end
    end
    empty!(KIT_CACHE)                       # don't store the loaded samples in the package image
end
