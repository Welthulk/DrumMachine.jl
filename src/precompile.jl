# Precompile workload: the methods of a typical start (presets, kit, rendering, building the
# window without displaying it) are compiled when the package is installed instead of at every
# start. Uses only the BlackPearl kit shipped with the package, no audio, no window.
using PrecompileTools: @setup_workload, @compile_workload

"""
    precompile_windows(song, kit; show = (fig, tick!) -> tick!())

Builds every window once without audio: main window (and its rebuild on a language switch),
running metronome, calibration and recording (live view and result), WAV editor with a file, setup player and setup editor with a one-song setup
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
    eng.seqout.sent = Tuple{Float64,Int32}[]                # sequencer through the MIDI output
    start_seq!(eng, [-1], 1)
    for _ in 1:20; render!(eng, zeros(Float32, BLOCK, 2)); end
    stop!(eng); eng.seqout.sent = nothing
    cfg = midi_config(Dict{String,Any}())                   # calibration: live view and result
    take = CalTake(0.0, 1.0)
    for i in 1:40; cal_add!(take, 1.0 + 0.1i, isodd(i) ? 4 : 2, 30 + 2i, isodd(i) ? 3 : 2, 10.0); end
    cp = preset("Einmessen").patterns[1]
    lfig, ltick! = with_theme(() -> cal_live_figure(take, cal_tracks(cp), cfg), DM_THEME)
    show(lfig, ltick!)
    rfig, _ = with_theme(() -> cal_result_figure(cal_result(take, cfg)), DM_THEME)
    show(rfig, () -> nothing)
    rt = RecTake(100, 4, 16, 0.0, 0.0)                     # recording: live view and result
    for k in 0:40; rec_add!(rt, 1.0, k * rt.steplen, isodd(k) ? 4 : 2, 80, 2); end
    rlfig, rltick! = with_theme(() -> rec_live_figure(RecSetup(100, 4, 4), () -> rt), DM_THEME)
    show(rlfig, rltick!)
    rs, ri = rec_song(rt; name = "R", kit = kit.name)
    rrfig, _ = with_theme(() -> rec_result_figure(rs, ri), DM_THEME)
    show(rrfig, () -> nothing)
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
            # the log (file only: nothing goes to the terminal during precompilation)
            lg = DMLogger(Logging.NullLogger(), joinpath(dir, "l.log"), open(joinpath(dir, "l.log"), "a"), 0, 300, ReentrantLock())
            try
                error("precompile")
            catch e
                write_log(lg, Logging.Error, "x", "f.jl", 1, [:exception => (e, catch_backtrace())])
            end
            write_log(lg, Logging.Info, "x", nothing, 0, [:a => 1, :b => "s"])
            Logging.handle_message(lg, Logging.Info, "x", @__MODULE__, :dmevent, :x, "f.jl", 1; a = 1)
            close(lg.io)
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
