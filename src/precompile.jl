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
            mktempdir() do dir      # WAV editor with a file, setup player and editor (synth kit)
                ps = copy(song); ps.kit = "808 (Synth)"; ps.repeats = 1
                wav = export_wav(joinpath(dir, "w.wav"), ps, kit_808(); repeats = 1)
                _, _, load! = with_theme(() -> wave_editor_figure(eng), DM_THEME)
                load!(wav)
                path = save_song(joinpath(dir, "p.toml"), ps)
                peng = Engine(Song(), kit)
                sl = Setlist("Precompile"); push!(sl.entries, SetEntry(path; pause = 0.5, beep = true))
                _, _, ptick!, _ = player_figures(peng, sl)
                player_start!(peng.player, 1; pause = true); peng.player.route = 2; peng.player.hall = 2
                mix_player!(peng.player, zeros(Float32, BLOCK, 2)); ptick!()
            end
        catch e
            @debug "precompile: build_gui failed" exception = e
        end
    end
    empty!(KIT_CACHE)                       # don't store the loaded samples in the package image
end
