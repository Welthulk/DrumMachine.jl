# Builds build/drummachine.so: GLMakie, PortAudio and WAV precompiled -> much faster startup.
#   julia tools/build_sysimage.jl        (takes a few minutes, then ./start_drum.sh)
# DrumMachine itself is not in the image, so code changes still take effect immediately.
# Rebuild after package updates (Manifest.toml changed).
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
