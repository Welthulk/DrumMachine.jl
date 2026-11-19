# Precompile workload: the methods of a typical start (presets, kit, rendering, building the
# window without displaying it) are compiled when the package is installed instead of at every
# start. Uses only the BlackPearl kit shipped with the package, no audio, no window.
using PrecompileTools: @setup_workload, @compile_workload

"""
    precompile_windows(song, kit; show = (fig, tick!) -> tick!())

Builds every window once without audio: main window (and its rebuild on a language switch),
running metronome, WAV editor with a file, setup player and setup editor with a one-song setup
(synth kit). `show(fig, tick!)` is called for each figure. Shared by the package workload below
and the sysimage workload in tools/precompile_workload.jl, which displays the windows.
"""
function precompile_windows(song, kit; show = (fig, tick!) -> tick!())
    fig, eng, tick! = build_gui(song; audio = false)
    show(fig, tick!)
    build_gui(song; audio = false, eng)                     # rebuild on language switch
    metro_start!(eng.metro)
    mfig, mtick! = with_theme(() -> metronome_figure(eng), DM_THEME)
    render!(eng, zeros(Float32, BLOCK, 2))
    show(mfig, mtick!)
    metro_stop!(eng.metro)
    mktempdir() do dir
        ps = copy(song); ps.kit = "808 (Synth)"; ps.repeats = 1
        wav = export_wav(joinpath(dir, "w.wav"), ps, kit_808(); repeats = 1)
        wfig, wtick!, load! = with_theme(() -> wave_editor_figure(eng), DM_THEME)
        load!(wav)
        show(wfig, wtick!)
        path = save_song(joinpath(dir, "p.toml"), ps)
        peng = Engine(Song(), kit)
        sl = Setlist("Precompile"); push!(sl.entries, SetEntry(path; pause = 0.5, beep = true))
        _, pfig, ptick!, efig = player_figures(peng, sl)
        player_start!(peng.player, 1; pause = true); peng.player.route = 2; peng.player.hall = 2
        mix_player!(peng.player, zeros(Float32, BLOCK, 2))
        show(pfig, ptick!)
        show(efig, () -> nothing)
    end
    return nothing
end

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
            export_midi(joinpath(dir, "t.mid"), song; repeats = 1)
            save_song(joinpath(dir, "t.toml"), song)
            load_song(joinpath(dir, "t.toml"))
        end
        kit_entries()
        precompile(midi_reader, (MidiInput,))   # compiled, not run: no MIDI device is opened here
        try
            precompile_windows(song, kit)
        catch e
            @warn "precompile: building the windows failed" exception = e
        end
    end
    empty!(KIT_CACHE)                       # don't store the loaded samples in the package image
end
