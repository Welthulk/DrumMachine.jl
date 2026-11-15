# Draws the program icon (practice pad with several zones) as PNG in several sizes
# into assets/icon/. Only needed when the icon is to be changed:
#   julia tools/build_icon.jl
using Pkg
Pkg.activate(; temp = true)
Pkg.add("CairoMakie")
using CairoMakie

const OUT = normpath(joinpath(@__DIR__, "..", "assets", "icon"))

# Colors matching the GUI
const BASE   = colorant"#16191e"   # base / housing
const EDGE   = colorant"#4a505b"
const RIM    = colorant"#3a404b"   # rim zone (hard, "rimshot")
const RIMHI  = colorant"#5a616d"
const GUM    = colorant"#e8771e"   # main zone (rubber)
const GUMDK  = colorant"#b85f18"
const INNER  = colorant"#ffb763"   # raised center (soft)
const STICK  = colorant"#e9d3ad"
const STICKD = colorant"#b39a72"

circ(r; c = (0.0, 0.0), n = 128) = [Point2f(c[1] + r * cospi(2k / n), c[2] + r * sinpi(2k / n)) for k in 0:n-1]
ring(r0, r1; c = (0.0, 0.0)) = (o = circ(r1; c); i = reverse(circ(r0; c)); Makie.Polygon(o, [i]))

"Stick as a polygon from `a` to `b`, width w, tip at end `b`."
function stick(a, b, w)
    d = Point2f(b) - Point2f(a); L = sqrt(sum(abs2, d)); u = d / L; nrm = Point2f(-u[2], u[1])
    tip = Point2f(b) - u * 0.12
    [Point2f(a) + nrm * w, tip + nrm * w * 0.8, Point2f(b) + nrm * w * 0.35, Point2f(b) - nrm * w * 0.35,
     tip - nrm * w * 0.8, Point2f(a) - nrm * w]
end

function icon(px::Int)
    fig = Figure(size = (px, px), backgroundcolor = :transparent, figure_padding = 0)
    ax = Axis(fig[1, 1], aspect = DataAspect(), backgroundcolor = :transparent,
              limits = (-0.5, 0.5, -0.5, 0.5))
    hidedecorations!(ax); hidespines!(ax)
    small = px <= 24
    lw = max(0.6, px / 128)

    # shadow + base
    poly!(ax, circ(0.47; c = (0.012, -0.018)), color = (:black, 0.35))
    poly!(ax, circ(0.47), color = BASE, strokecolor = EDGE, strokewidth = lw)
    # rim zone with grooves
    poly!(ax, ring(0.36, 0.44), color = RIM)
    if !small
        for k in 0:23
            a = k / 12
            lines!(ax, [Point2f(0.375cospi(a), 0.375sinpi(a)), Point2f(0.425cospi(a), 0.425sinpi(a))],
                   color = RIMHI, linewidth = lw)
        end
    end
    # main rubber zone, split into two halves (two playing feels)
    poly!(ax, circ(0.34), color = GUM)
    poly!(ax, [Point2f(0.34cospi(t), 0.34sinpi(t)) for t in range(-0.25, 0.75, length = 65)], color = GUMDK)
    # raised center
    poly!(ax, circ(0.15; c = (0.006, -0.009)), color = (:black, 0.3))
    poly!(ax, circ(0.15), color = INNER, strokecolor = GUMDK, strokewidth = lw)
    small || poly!(ax, circ(0.035), color = GUM)
    # crossed sticks (from 32 px up)
    if px >= 32
        w = 0.022
        for (a, b) in (((-0.47, -0.30), (0.20, 0.36)), ((0.47, -0.30), (-0.20, 0.36)))
            poly!(ax, stick(a, b, w), color = STICK, strokecolor = STICKD, strokewidth = lw)
        end
    end
    return fig
end

mkpath(OUT)
for px in (16, 24, 32, 48, 64, 128, 256)
    # drawing 32 px directly triggers a stack overflow in CairoMakie -> downscale from 64 px
    fig, ppu = px == 32 ? (icon(64), 0.5) : (icon(px), 1)
    save(joinpath(OUT, "drummachine_$(px).png"), fig; px_per_unit = ppu)
end
println("Icons geschrieben nach $OUT")
