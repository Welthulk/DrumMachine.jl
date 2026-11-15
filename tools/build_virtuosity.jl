# Builds the kit "VirtuosityDrums" (jazz kit by Versilian Studios / Karoryfer, CC0).
# The program does this automatically on first start; this script is for a manual (re)build.
#
#   julia --project=. tools/build_virtuosity.jl           # downloads (1.2 GB) and builds
#   julia --project=. tools/build_virtuosity.jl /path/to/extracted/folder
#
# Result: ~/.local/share/DrumMachine/kits/VirtuosityDrums (DRUMMACHINE_KIT_DIR overrides the
# folder). Extracted with `bsdtar` or `unzip`; FLAC is decoded with the flac from FLAC_jll.
using DrumMachine
DrumMachine.build_virtuosity(; src = isempty(ARGS) ? nothing : ARGS[1])
