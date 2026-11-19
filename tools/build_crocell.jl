# Builds the kit "CrocellKit" from the stereo mix of the DrumGizmo CrocellKit (CC BY 4.0).
# The program builds it when chosen in the kit menu (or at start with `auto_kits = true`); this
# script is for a manual (re)build.
#
#   julia --project=. tools/build_crocell.jl                 # downloads (561 MB) and builds
#   julia --project=. tools/build_crocell.jl /path/CrocellKit_Stereo_MIX   # already extracted
#
# Result: ~/.local/share/DrumMachine/kits/CrocellKit (~70 MB; DRUMMACHINE_KIT_DIR overrides the
# folder). The RAR archive is extracted with bsdtar from LibArchive_jll.
using DrumMachine
# the lock keeps the app (or a second script) from building the same kit at the same time
DrumMachine.kit_lock("CrocellKit") do
    DrumMachine.build_crocell(; src = isempty(ARGS) ? nothing : ARGS[1])
end || println("CrocellKit is being built by another DrumMachine process.")
