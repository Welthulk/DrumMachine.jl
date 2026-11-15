# Baut build/drummachine.so: GLMakie, PortAudio und WAV vorkompiliert → deutlich schnellerer Start.
#   julia tools/build_sysimage.jl        (dauert einige Minuten, danach ./start_drum.sh)
# DrumMachine selbst ist nicht im Image, Änderungen am Code wirken also weiterhin sofort.
# Nach Paket-Updates (Manifest.toml geändert) neu bauen.
using Pkg
root = normpath(joinpath(@__DIR__, ".."))
Pkg.activate(; temp = true)
Pkg.add("PackageCompiler")
using PackageCompiler

mkpath(joinpath(root, "build"))
create_sysimage([:GLMakie, :PortAudio, :WAV];
                project = root,
                sysimage_path = joinpath(root, "build", "drummachine.so"),
                precompile_execution_file = joinpath(@__DIR__, "precompile_workload.jl"))
println("Fertig: build/drummachine.so – Start mit ./start_drum.sh")
