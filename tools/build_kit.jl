# Downloads and builds one or more of the downloadable kits by name (same as choosing them in the
# kit menu). Without arguments: list of the kits and whether they are installed.
#
#   julia --project=. tools/build_kit.jl                    # list
#   julia --project=. tools/build_kit.jl DRSKit MuldjordKit
#   julia --project=. tools/build_kit.jl all                # every kit that is not installed yet
using DrumMachine
const D = DrumMachine
installed(n) = any(e -> e.name == n, D.kit_entries())
if isempty(ARGS)
    for (name, size, _, auto, kits) in D.DOWNLOADABLE_KITS
        println(rpad(name, 18), lpad(size, 8), auto ? "  auto     " : "  on demand", all(installed, kits) ? "  installed" : "",
                kits == [name] ? "" : "  (" * join(kits, ", ") * ")")
    end
else
    names = ARGS == ["all"] ? [k[1] for k in D.missing_kits()] : ARGS
    for n in names
        k = findfirst(x -> x[1] == n, D.DOWNLOADABLE_KITS)
        k === nothing && (println("unknown kit: ", n); continue)
        D.fetch_kit(D.DOWNLOADABLE_KITS[k], println, _ -> nothing)
    end
end
