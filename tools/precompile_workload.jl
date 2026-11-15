# Typical program run without audio, so PackageCompiler compiles the required methods.
# Run by tools/build_sysimage.jl.
using DrumMachine
const D = DrumMachine

song = preset("Funk: What-Is-Hip-Stil (Tower of Power)")
kit = first(available_kits())
render_song(song, kit; repeats = 1)
mktempdir() do dir
    export_wav(joinpath(dir, "test.wav"), song, kit)
    save_song(joinpath(dir, "test.toml"), song)
    load_song(joinpath(dir, "test.toml"))
end
make_fill(song.patterns[1], song.steps_per_beat, 2)

D.GLMakie.activate!(title = "DrumMachine.jl")
fig, eng, tick! = D.build_gui(song; audio = false)
tick!()
try                                   # open the window briefly (only possible with OpenGL)
    screen = display(fig)
    for _ in 1:30
        tick!(); sleep(1 / 60)
    end
    close(screen)
catch e
    @warn "Fenster ließ sich nicht öffnen – Sysimage enthält dann weniger Grafik-Code" exception = e
end
