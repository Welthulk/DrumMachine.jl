# Builds the kit "VirtuosityDrums" (jazz kit by Versilian Studios / Karoryfer, CC0).
# The program builds it when chosen in the kit menu (or at start with `auto_kits = true`); this
# script is for a manual (re)build.
#
#   julia --project=. tools/build_virtuosity.jl           # downloads (1.2 GB) and builds
#   julia --project=. tools/build_virtuosity.jl /path/to/extracted/folder
#
# Result: ~/.local/share/DrumMachine/kits/VirtuosityDrums (DRUMMACHINE_KIT_DIR overrides the
# folder). Extracted with bsdtar from LibArchive_jll; FLAC is decoded with the flac from FLAC_jll.
using DrumMachine
# the lock keeps the app (or a second script) from building the same kit at the same time
DrumMachine.kit_lock("VirtuosityDrums") do
    DrumMachine.build_virtuosity(; src = isempty(ARGS) ? nothing : ARGS[1])
end || println("VirtuosityDrums is being built by another DrumMachine process.")
