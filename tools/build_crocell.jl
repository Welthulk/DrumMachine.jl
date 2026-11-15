# Builds the kit "CrocellKit" from the stereo mix of the DrumGizmo CrocellKit (CC BY 4.0).
# The program does this automatically on first start; this script is for a manual (re)build.
#
#   julia --project=. tools/build_crocell.jl                 # downloads (561 MB) and builds
#   julia --project=. tools/build_crocell.jl /path/CrocellKit_Stereo_MIX   # already extracted
#
# Result: ~/.local/share/DrumMachine/kits/CrocellKit (~70 MB; DRUMMACHINE_KIT_DIR overrides the
# folder). Extracting the RAR archive requires `bsdtar` (libarchive-tools) or `unrar`.
using DrumMachine
DrumMachine.build_crocell(; src = isempty(ARGS) ? nothing : ARGS[1])
