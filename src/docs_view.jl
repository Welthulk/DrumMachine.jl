# Documentation viewer: shows the Markdown files from docs/ inside the app (window "Docs").
# Markdown is turned into plain, wrapped text pages; tables become compact per-row blocks so that
# they fit the window. Each `##`/`###` heading starts a new page.

using Markdown

const DOCS_DIR = normpath(joinpath(@__DIR__, "..", "docs"))
const DOC_WIDTH = 88                       # characters per line in the viewer

"Wraps `s` to `width` characters, every line prefixed with `indent`."
function wrap_text(s::AbstractString, width::Int; indent::AbstractString = "")
    words = split(replace(s, r"\s+" => " "))
    lines = String[]; cur = ""
    for w in words
        if isempty(cur)
            cur = indent * w
        elseif length(cur) + 1 + length(w) <= width
            cur *= " " * w
        else
            push!(lines, cur); cur = indent * w
        end
    end
    isempty(cur) || push!(lines, cur)
    return join(lines, "\n")
end

"Inline Markdown as plain text: code ticks and emphasis markers removed."
function inline_text(x)
    s = strip(Markdown.plaininline(x))
    s = replace(s, r"!\[[^\]]*\]\([^)]*\)" => "")                # images are not shown in the viewer
    s = replace(s, r"\[([^\]]+)\]\(([^)]+)\)" => s"\1 (\2)")   # [text](url) -> text (url)
    s = replace(s, "`" => "")
    s = replace(s, r"\*\*(.+?)\*\*" => s"\1")
    s = replace(s, r"(?<![\w*])\*([^*\s][^*]*?)\*(?![\w*])" => s"\1")
    return s
end
cell_text(c) = inline_text(c isa AbstractVector ? c : [c])

"Plain-text rendering of one Markdown block (without headings)."
function block_text(b, width::Int)
    if b isa Markdown.Paragraph
        t = inline_text(b.content)
        return isempty(t) ? "" : wrap_text(t, width)
    elseif b isa Markdown.Code
        return join(("    " * l for l in split(b.code, '\n')), "\n")
    elseif b isa Markdown.BlockQuote
        inner = join((block_text(x, width - 4) for x in b.content), "\n\n")
        return join(("  │ " * l for l in split(inner, '\n')), "\n")
    elseif b isa Markdown.List
        items = String[]
        for (k, it) in enumerate(b.items)
            mark = b.ordered == -1 ? "•" : "$(b.ordered + k - 1)."
            txt = join((block_text(x, width - 4) for x in it), "\n")
            ls = split(txt, '\n')
            push!(items, "  $mark " * ls[1] * join(("\n    " * l for l in ls[2:end])))
        end
        return join(items, "\n")
    elseif b isa Markdown.Table
        # header row, then one block per row: first column, middle columns as "Header: value",
        # last column as wrapped description
        head = [cell_text(c) for c in b.rows[1]]
        out = String[]
        for row in b.rows[2:end]
            cells = [cell_text(c) for c in row]
            n = length(cells)
            n == 1 && (push!(out, "  " * cells[1]); continue)
            lines = ["  " * cells[1]]
            if n > 2
                push!(lines, wrap_text(join(("$(head[k]): $(cells[k])" for k in 2:n-1), " · "), width; indent = "      "))
            end
            push!(lines, wrap_text(cells[n], width; indent = "      "))
            push!(out, join(lines, "\n"))
        end
        return join(out, "\n")
    elseif b isa Markdown.HorizontalRule
        return "─"^min(width, 40)
    else
        return wrap_text(strip(Markdown.plain(b)), width)
    end
end

"""
    doc_pages(path; width) -> (title, pages)

Splits a Markdown file into pages at every `##`/`###` heading. Returns the document title
(the `#` heading) and a vector of `(heading, text)` pairs; text before the first `##` becomes
the page "Overview".
"""
function doc_pages(path::AbstractString; width::Int = DOC_WIDTH)
    md = Markdown.parse(read(path, String))
    title = splitext(basename(path))[1]
    pages = Tuple{String,String}[]
    cur = "Overview"; buf = String[]
    flush!() = (txt = strip(join(filter(!isempty, buf), "\n\n"), '\n'); isempty(txt) || push!(pages, (cur, txt)); empty!(buf))
    for b in md.content
        if b isa Markdown.Header
            lvl = typeof(b).parameters[1]
            if lvl == 1
                title = inline_text(b.text)
            else
                flush!(); cur = inline_text(b.text)
            end
        else
            push!(buf, block_text(b, width))
        end
    end
    flush!()
    return title, pages
end

"All Markdown documents in docs/ as (file name, title, pages), sorted by file name."
function load_docs(dir::AbstractString = DOCS_DIR)
    isdir(dir) || return Tuple{String,String,Vector{Tuple{String,String}}}[]
    [(f, doc_pages(joinpath(dir, f))...) for f in sort(readdir(dir)) if endswith(f, ".md")]
end

# ---------------------------------------------------------------------------
# Window
# ---------------------------------------------------------------------------

"Figure of the documentation viewer: documents and pages on the left, text on the right."
docs_figure(docs = load_docs()) = with_theme(DM_THEME) do
    f = Figure(size = (1040, 800), figure_padding = 16)
    if isempty(docs)
        Label(f[1, 1], L("Keine Dokumentation gefunden in {1}", DOCS_DIR), color = C_TEXT2)
        return f
    end
    bar = f[1, 1:2] = GridLayout(halign = :left, tellwidth = false)
    doc_title = Label(bar[1, 1], "", font = :bold, fontsize = 18, color = C_TEXT)
    webbtn = Button(bar[1, 2], label = L("Auf GitHub lesen ↗"), height = 32, fontsize = 13)
    path_lab = Label(bar[1, 3], "", color = C_DIM, fontsize = 12, padding = (12, 0, 0, 0))

    nav = f[2, 1] = GridLayout(valign = :top, halign = :left, width = 230, tellheight = false)
    panel!(f[2, 2])
    txt = Observable("")
    Label(f[2, 2], txt; font = "DejaVu Sans Mono", fontsize = 13, justification = :left,
          halign = :left, valign = :top, color = C_TEXT, padding = (22, 22, 20, 20),
          tellwidth = false, tellheight = false)

    # one button per page, grouped by document
    cur = Ref((1, 1))
    pagebtns = Dict{Tuple{Int,Int},Button}()
    row = 0
    for (d, (file, title, pages)) in enumerate(docs)
        Label(nav[row += 1, 1], uppercase(title), font = :bold, color = C_TEXT2, fontsize = 12,
              halign = :left, padding = (0, 0, 4, row == 1 ? 0 : 12))
        for (p, (heading, _)) in enumerate(pages)
            b = Button(nav[row += 1, 1], label = heading, width = 220, halign = :left, fontsize = 13)
            pagebtns[(d, p)] = b
            on(_ -> show_page(d, p), b.clicks)
        end
    end
    rowgap!(nav, 4)
    colsize!(f.layout, 1, Fixed(230))
    rowsize!(f.layout, 1, Fixed(40))

    function show_page(d, p)
        file, title, pages = docs[d]
        cur[] = (d, p)
        doc_title.text[] = title
        path_lab.text[] = joinpath("docs", file)
        txt[] = pages[p][2]
        for ((dd, pp), b) in pagebtns
            on_page = (dd, pp) == (d, p)
            b.buttoncolor[] = on_page ? C_ACTIVE : C_BTN
            b.labelcolor[] = on_page ? C_BG : C_TEXT
        end
    end
    on(webbtn.clicks) do _
        open_url("$REPO_URL/blob/main/docs/$(docs[cur[][1]][1])")
    end
    show_page(1, 1)
    f
end

"Opens the documentation window."
function show_docs()
    screen = display(GLMakie.Screen(; title = "DrumMachine – Docs"), docs_figure())
    set_icon!(screen)
    return screen
end
