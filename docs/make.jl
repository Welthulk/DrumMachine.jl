# Builds the documentation website (Documenter.jl) from docs/*.md, the API reference
# docs/src/api.md (docstrings of the exported functions) and the top-level
# FEATURES.md, PLATFORMS.md, KITS.md, CHANGELOG.md and SUPPORT.md.
# The program shows the same docs/*.md in its Docs window, so they stay plain markdown: this
# script copies everything into a temporary source folder and fixes the relative links.
#
#   julia --project=docs -e 'using Pkg; Pkg.instantiate()'
#   julia --project=docs docs/make.jl            -> docs/build (deploys only on GitHub Actions)
using Documenter, DrumMachine

const ROOT = normpath(joinpath(@__DIR__, ".."))
const REPO = "https://github.com/Welthulk/DrumMachine.jl"
const DOCS = ["song-format.md", "wav-editor.md", "metronome.md", "player.md", "midi.md"]
const TOP = ["FEATURES.md", "PLATFORMS.md", "KITS.md", "CHANGELOG.md", "SUPPORT.md"]

"Relative links that point outside the website go to GitHub, docs/x becomes x."
function fix_links(text::AbstractString)
    text = replace(text, r"\]\(docs/([\w.-]+)\)" => s"](\1)")
    text = replace(text, r"\]\(docs\)" => "]($REPO/tree/main/docs)")
    text = replace(text, r"\]\(\.\./songs/?\)" => "]($REPO/tree/main/songs)")
    text = replace(text, r"\]\((README(\.de)?\.md|LICENSE)\)" => s -> "]($REPO/blob/main/" * s[3:end-1] * ")")
    return text
end

const INDEX = """
# DrumMachine.jl

Step sequencer in Julia for drum practice: enter a groove, listen to it, export it as WAV and play along.

![Screenshot](screenshot.png)

The program shows a short help (**?**) and these pages (*Docs*) itself. Installation and start:
[README]($REPO#readme) ([Deutsch]($REPO/blob/main/README.de.md)).

| Page | Content |
|---|---|
| [Features](FEATURES.md) | everything the program can do |
| [Song format](song-format.md) | the TOML song files, all keys |
| [WAV editor](wav-editor.md) | editing exported WAV files |
| [Metronome](metronome.md) | the metronome window |
| [Setup player](player.md) | playing songs on stage |
| [MIDI recording and export](midi.md) | recording from an e-drum kit (Roland TD-27), MIDI file export |
| [Kits](KITS.md) | sample kits, sources and licenses |
| [Platforms](PLATFORMS.md) | Linux, Windows, macOS, required programs |
| [Changelog](CHANGELOG.md) | changes per version |
| [API](api.md) | the exported functions for scripts |
| [Support](SUPPORT.md) | how to help |
"""

src = mktempdir()
write(joinpath(src, "index.md"), INDEX)
for f in DOCS
    write(joinpath(src, f), fix_links(read(joinpath(ROOT, "docs", f), String)))
end
for f in TOP
    write(joinpath(src, f), fix_links(read(joinpath(ROOT, f), String)))
end
cp(joinpath(@__DIR__, "src", "api.md"), joinpath(src, "api.md"))
for f in readdir(joinpath(ROOT, "docs"))
    endswith(f, ".png") && !endswith(f, "-de.png") && cp(joinpath(ROOT, "docs", f), joinpath(src, f))
end

makedocs(;
    sitename = "DrumMachine.jl",
    modules = [DrumMachine],
    checkdocs = :exports,              # every exported name must appear in api.md
    source = src,
    build = joinpath(@__DIR__, "build"),
    repo = Remotes.GitHub("Welthulk", "DrumMachine.jl"),
    format = Documenter.HTML(; prettyurls = get(ENV, "CI", "false") == "true",
                              canonical = "https://welthulk.github.io/DrumMachine.jl", edit_link = nothing,
                              repolink = REPO),
    pages = [
        "Home" => "index.md",
        "Features" => "FEATURES.md",
        "Song format" => "song-format.md",
        "WAV editor" => "wav-editor.md",
        "Metronome" => "metronome.md",
        "Setup player" => "player.md",
        "MIDI" => "midi.md",
        "Kits" => "KITS.md",
        "Platforms" => "PLATFORMS.md",
        "API" => "api.md",
        "Changelog" => "CHANGELOG.md",
        "Support" => "SUPPORT.md",
    ],
    remotes = nothing,                 # the sources live in a temporary folder, no "edit" links
    doctest = false,
)

deploydocs(; repo = "github.com/Welthulk/DrumMachine.jl.git", devbranch = "main", push_preview = false)
