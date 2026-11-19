# Builds build/drummachine.so: GLMakie, PortAudio and WAV precompiled -> much faster startup.
#   julia tools/build_sysimage.jl        (takes a few minutes, then ./start_drum.sh)
# DrumMachine itself is not in the image, so code changes still take effect immediately.
# Rebuild after package or Julia updates; ./start_drum.sh detects both through build/manifest.key.
using Pkg
root = normpath(joinpath(@__DIR__, ".."))

"""
Key of the image: the exact Julia build, then Manifest.toml without DrumMachine's own entry and
without `project_hash` (the same filter as `manifest_key` in start_drum.sh, which compares it).
"""
function image_key(manifest)
    io = IOBuffer()
    println(io, VERSION, "+", Base.GIT_VERSION_INFO.commit)
    skip = false
    for line in eachline(manifest)
        if startswith(line, "[[deps.DrumMachine]]")
            skip = true
            continue
        end
        startswith(line, "[") && (skip = false)
        skip || startswith(line, "project_hash") || println(io, line)
    end
    String(take!(io))
end

key = image_key(joinpath(root, "Manifest.toml"))     # state the image is built from
keyfile = joinpath(root, "build", "manifest.key")

Pkg.activate(; temp = true)
Pkg.add("PackageCompiler")
using PackageCompiler

mkpath(joinpath(root, "build"))
create_sysimage([:GLMakie, :PortAudio, :WAV];
                project = root,
                sysimage_path = joinpath(root, "build", "drummachine.so"),
                precompile_execution_file = joinpath(@__DIR__, "precompile_workload.jl"))
write(keyfile, key)
println("Fertig: build/drummachine.so – Start mit ./start_drum.sh")
