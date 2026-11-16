# Start:  julia -t auto --project=. run.jl            (main window)
#         julia -t auto --project=. run.jl --player   (only the setup player, for the stage)
using DrumMachine
"--player" in ARGS ? DrumMachine.player() : DrumMachine.run()
