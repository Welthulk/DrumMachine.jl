# Typical program run without audio, so PackageCompiler compiles the required methods.
# Run by tools/build_sysimage.jl. Every window of the program is built and, if OpenGL is
# available, shown briefly: main window, metronome, WAV editor, setup player, setup editor.
using DrumMachine
const D = DrumMachine

song = preset("Funk: What-Is-Hip-Stil (Tower of Power)")
kit = first(available_kits())
render_song(song, kit; repeats = 1)
make_fill(song.patterns[1], song.steps_per_beat, 2)

D.GLMakie.activate!(title = "DrumMachine.jl")

"Shows `fig` for a moment and calls `tick!` like the window loop does (only with OpenGL)."
function show_briefly(fig, tick!; frames = 30)
    tick!()
    try
        screen = display(D.GLMakie.Screen(), fig)
        for _ in 1:frames
            tick!(); sleep(1 / 60)
        end
        close(screen)
    catch e
        @warn "Fenster ließ sich nicht öffnen – Sysimage enthält dann weniger Grafik-Code" exception = e
    end
end

mktempdir() do dir
    wav = export_wav(joinpath(dir, "test.wav"), song, kit; repeats = 1)
    save_song(joinpath(dir, "test.toml"), song)
    load_song(joinpath(dir, "test.toml"))

    # main window
    fig, eng, tick! = D.build_gui(song; audio = false)
    show_briefly(fig, tick!)

    # metronome, running
    D.metro_start!(eng.metro)
    mfig, mtick! = D.with_theme(() -> D.metronome_figure(eng), D.DM_THEME)
    D.render!(eng, zeros(Float32, D.BLOCK, 2))
    show_briefly(mfig, mtick!)
    D.metro_stop!(eng.metro)

    # WAV editor with the exported file
    wfig, wtick!, load! = D.with_theme(() -> D.wave_editor_figure(eng), D.DM_THEME)
    load!(wav)
    show_briefly(wfig, wtick!)

    # setup player and setup editor: a short one-song setup (synth kit), rendered and played a little
    ps = copy(song); ps.kit = "808 (Synth)"; ps.repeats = 1
    path = save_song(joinpath(dir, "p.toml"), ps)
    peng = Engine(Song(), kit)
    sl = D.Setlist("Precompile"); push!(sl.entries, D.SetEntry(path; pause = 0.5, beep = true))
    _, pfig, ptick!, efig = D.player_figures(peng, sl)
    D.player_start!(peng.player, 1; pause = true); peng.player.route = 2; peng.player.hall = 2
    D.mix_player!(peng.player, zeros(Float32, D.BLOCK, 2))
    show_briefly(pfig, ptick!)
    show_briefly(efig, () -> nothing)
end
