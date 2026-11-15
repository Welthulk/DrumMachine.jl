# Checks the translations: every L("…") key in src/ must have an English entry, and string
# literals with German text that are not passed through L are listed as candidates. Lines with
# the comment `# i18n-ok` are skipped (identifiers, or keys translated where they are displayed).
#   julia --project=. tools/check_i18n.jl [file …]
using DrumMachine
const EN = DrumMachine.EN
files = isempty(ARGS) ? filter(endswith(".jl"), readdir(joinpath(@__DIR__, "..", "src"); join = true)) : ARGS
strlit = r"\"((?:[^\"\\]|\\.)*)\""
german = r"[äöüÄÖÜß]|\b(?:der|die|das|und|nicht|wird|mit|für|oder|auf|bei|nur|noch|keine?|Datei|Spur|Takt|Schlag|Auswahl|Fehler|geladen|gespeichert|Speichern|Laden|Löschen|Neu)\b"
function check(files)
nmiss = 0; ncand = 0
for f in files
    endswith(f, "i18n.jl") && continue
    occursin("/lang/", f) && continue
    lines = readlines(f)
    for (n, line) in enumerate(lines)
        code = replace(line, r"#[^\"]*$" => "")                      # drop trailing comments
        startswith(strip(line), "#") && continue
        occursin("# i18n-ok", line) && continue                     # marked: identifier / translated elsewhere
        for m in eachmatch(r"L\(\s*\"((?:[^\"\\]|\\.)*)\"", code)
            key = unescape_string(m.captures[1])
            occursin('$', m.captures[1]) && (println("$f:$n  L() key with \$ interpolation (use {1}): ", key); nmiss += 1; continue)
            haskey(EN, key) || (println("$f:$n  missing English: ", repr(key)); nmiss += 1)
        end
        for m in eachmatch(strlit, code)
            s = m.captures[1]
            pre = code[1:m.offset-1]
            occursin(r"L\(\s*$", pre) && continue                       # already translated
            occursin(german, s) || continue
            println("$f:$n  German literal not in L(): ", repr(s)); ncand += 1
        end
    end
end
println("\n$nmiss missing translations, $ncand German literals outside L()")
return nmiss, ncand
end
check(files)
