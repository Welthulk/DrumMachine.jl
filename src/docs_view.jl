# Documentation viewer: shows the Markdown files from docs/ inside the app (window "Docs").
# Markdown is turned into plain, wrapped text pages; tables become compact per-row blocks so that
# they fit the window. Each `##`/`###` heading starts a new page; a section longer than the window
# is split at paragraph boundaries into several pages ("Heading (1/2)").

using Markdown

const DOCS_DIR = normpath(joinpath(@__DIR__, "..", "docs"))
const DOC_WIDTH = 88                       # characters per line in the viewer
const DOC_LINES = 40                       # lines per page that fit the window

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

"A line that starts a new item (table row, list entry, paragraph): indented by at most 2."
item_start(l::AbstractString) = !isempty(strip(l)) && length(l) - length(lstrip(l)) <= 2

"""
    split_lines(txt, maxlines) -> Vector{String}

Splits a page text into chunks of at most `maxlines` lines. Blocks (separated by blank lines)
stay together where possible; a block that does not fit on a page of its own (a long table) fills
the current page and is cut before a new table row or list entry, as does a block that would
leave a page with only a few lines.
"""
function split_lines(txt::AbstractString, maxlines::Int)
    chunks = String[]; cur = SubString{String}[]
    flush!() = (isempty(cur) || push!(chunks, join(cur, "\n")); empty!(cur))
    room() = isempty(cur) ? maxlines : maxlines - length(cur) - 1
    add!(ls) = (isempty(cur) || push!(cur, ""); append!(cur, ls))
    for para in split(String(txt), "\n\n")
        ls = split(para, '\n')
        if length(ls) <= room()
            add!(ls)
        elseif length(ls) <= maxlines && (length(cur) >= 8 || !any(item_start, @view ls[2:end]))
            flush!(); add!(ls)                          # block gets a page of its own
        else
            while !isempty(ls)
                r = room()
                length(ls) <= r && (add!(ls); break)
                k = findlast(item_start, @view ls[2:min(r + 1, end)])   # cut before line k+1
                n = k === nothing || (k < 3 && !isempty(cur)) ? (isempty(cur) ? r : 0) : k
                n > 0 && (add!(ls[1:n]); ls = ls[n+1:end])
                flush!()
            end
        end
    end
    flush!()
    return chunks
end

"""
    doc_pages(path; width, lines) -> (title, pages)

Splits a Markdown file into pages at every `##`/`###` heading. Returns the document title
(the `#` heading) and a vector of `(heading, text)` pairs; text before the first `##` becomes
the page "Overview". A section with more than `lines` lines becomes several pages, headed
"Heading (1/2)", "Heading (2/2)". A file without any text gets one empty "Overview" page.
"""
function doc_pages(path::AbstractString; width::Int = DOC_WIDTH, lines::Int = DOC_LINES)
    md = Markdown.parse(read(path, String))
    title = splitext(basename(path))[1]
    pages = Tuple{String,String}[]
    cur = "Overview"; buf = String[]
    function flush!()
        txt = strip(join(filter(!isempty, buf), "\n\n"), '\n')
        empty!(buf)
        isempty(txt) && return
        parts = split_lines(txt, lines)
        n = length(parts)
        for (k, part) in enumerate(parts)
            push!(pages, (n == 1 ? cur : "$cur ($k/$n)", part))
        end
    end
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
    isempty(pages) && push!(pages, ("Overview", ""))   # a stub with only a title still gets one page
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

"""
Figure of the documentation viewer: one button per document at the top, the pages of the chosen
document on the left, the text on the right. ◀ ▶ and the arrow keys turn the pages.
"""
docs_figure(docs = load_docs()) = with_theme(DM_THEME) do
    f = Figure(size = (1040, 800), figure_padding = 16)
    if isempty(docs)
        Label(f[1, 1], L("Keine Dokumentation gefunden in {1}", DOCS_DIR), color = C_TEXT2)
        return f
    end
    bar = f[1, 1:2] = GridLayout(halign = :left, tellwidth = false)
    docbtns = [Button(bar[1, d], label = title, height = 32, fontsize = 13) for (d, (_, title, _)) in enumerate(docs)]
    nd = length(docs)
    prevbtn = Button(bar[1, nd+1], label = "◀", height = 32, width = 40, fontsize = 13)
    nextbtn = Button(bar[1, nd+2], label = "▶", height = 32, width = 40, fontsize = 13)
    pagelab = Label(bar[1, nd+3], "", color = C_TEXT2, fontsize = 13)
    webbtn = Button(bar[1, nd+4], label = L("Auf GitHub lesen ↗"), height = 32, fontsize = 13)
    colgap!(bar, 6)
    colgap!(bar, nd, 18)

    nav = f[2, 1] = GridLayout(valign = :top, halign = :left, width = 230, tellheight = false)
    panel!(f[2, 2])
    txt = Observable("")
    Label(f[2, 2], txt; font = "DejaVu Sans Mono", fontsize = 13, justification = :left,
          halign = :left, valign = :top, color = C_TEXT, padding = (22, 22, 20, 20),
          tellwidth = false, tellheight = false)

    # page buttons of the current document: one pool, labels change with the document
    path_lab = Label(nav[1, 1], "", color = C_DIM, fontsize = 12, halign = :left)
    npool = maximum(length(pages) for (_, _, pages) in docs)
    pagebtns = [Button(nav[k+1, 1], label = " ", width = 220, halign = :left, fontsize = 13) for k in 1:npool]
    rowgap!(nav, 4)
    colsize!(f.layout, 1, Fixed(230))
    rowsize!(f.layout, 1, Fixed(40))

    cur = Ref((1, 1))
    function show_page(d, p)
        file, title, pages = docs[d]
        p = clamp(p, 1, length(pages))
        cur[] = (d, p)
        path_lab.text[] = joinpath("docs", file)
        txt[] = pages[p][2]
        pagelab.text[] = L("Seite {1}/{2}", p, length(pages))
        for (k, b) in enumerate(docbtns)
            b.buttoncolor[] = k == d ? C_ACTIVE : C_BTN
            b.labelcolor[] = k == d ? C_BG : C_TEXT
        end
        for (k, b) in enumerate(pagebtns)
            b.blockscene.visible[] = k <= length(pages)
            k <= length(pages) && (b.label[] = pages[k][1])
            b.buttoncolor[] = k == p ? C_ACTIVE : C_BTN
            b.labelcolor[] = k == p ? C_BG : C_TEXT
        end
    end
    npages() = length(docs[cur[][1]][3])
    turn!(δ) = show_page(cur[][1], cur[][2] + δ)
    for (d, b) in enumerate(docbtns)
        on(_ -> show_page(d, 1), b.clicks)
    end
    for (k, b) in enumerate(pagebtns)
        on(_ -> k <= npages() && show_page(cur[][1], k), b.clicks)
    end
    on(_ -> turn!(-1), prevbtn.clicks)
    on(_ -> turn!(1), nextbtn.clicks)
    on(events(f).keyboardbutton) do ev
        ev.action in (Keyboard.press, Keyboard.repeat) || return
        ev.key in (Keyboard.left, Keyboard.page_up) && turn!(-1)
        ev.key in (Keyboard.right, Keyboard.page_down) && turn!(1)
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
