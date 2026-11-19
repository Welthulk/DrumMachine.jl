# Typical program run without audio, so PackageCompiler compiles the required methods.
# Run by tools/build_sysimage.jl. Every window of the program is built and, if OpenGL is
# available, shown briefly: main window, metronome, WAV editor, setup player, setup editor
# (DrumMachine.precompile_windows, the same code as the package's own precompile workload).
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
    export_wav(joinpath(dir, "test.wav"), song, kit; repeats = 1)
    save_song(joinpath(dir, "test.toml"), song)
    load_song(joinpath(dir, "test.toml"))
end

# every window, shown briefly; no try/catch here, so a changed API stops the build loudly
D.precompile_windows(song, kit; show = show_briefly)
