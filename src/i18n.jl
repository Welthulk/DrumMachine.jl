# User interface language (German / English).
#
# All user-visible strings are written in German in the source and passed through `L`:
#     L("Speichern")                    -> "Save" when the language is English
#     L("Geladen: {1}", path)           -> "Loaded: /x.toml"  ({1}, {2}, … are filled with the args)
# English texts live in the dictionaries in src/lang/ (German text => English text). A string
# without an entry is shown in German, so a missing translation never breaks the GUI.
#
# The default language follows the system locale (LC_ALL, LC_MESSAGES, LANG, LANGUAGE): German
# for "de…", English otherwise. A choice made in the GUI is stored in the settings file and
# wins over the locale.

import TOML

const LANGS = (:de, :en)
const LANG = Ref(:de)
const EN = Dict{String,String}()          # filled by src/lang/*.jl

"Language from the system locale: :de for a German locale, :en otherwise."
function locale_lang(env = ENV)
    for var in ("LC_ALL", "LC_MESSAGES", "LANG", "LANGUAGE")
        v = get(env, var, "")
        isempty(v) && continue
        v in ("C", "POSIX") && return :en
        return startswith(lowercase(v), "de") ? :de : :en
    end
    return :en
end

"Settings file (XDG config directory)."
settings_path() = joinpath(get(ENV, "XDG_CONFIG_HOME", joinpath(homedir(), ".config")), "DrumMachine", "settings.toml")

function load_settings()
    p = settings_path()
    isfile(p) || return Dict{String,Any}()
    try
        return TOML.parsefile(p)
    catch e
        @warn "Settings file unreadable, ignored" path = p exception = e
        return Dict{String,Any}()
    end
end

function save_setting!(key::AbstractString, value)
    d = load_settings()
    d[String(key)] = value
    p = settings_path()
    try
        mkpath(dirname(p))
        open(io -> TOML.print(io, d), p, "w")
    catch e
        @warn "Settings could not be saved" path = p exception = e
    end
    return d
end

"Language at start: stored choice, otherwise the system locale."
function initial_lang()
    s = get(load_settings(), "language", "")
    s in ("de", "en") ? Symbol(s) : locale_lang()
end

"Sets the language (`:de` or `:en`); `persist = true` stores it in the settings file."
function set_lang!(lang::Symbol; persist::Bool = false)
    lang in LANGS || error("unknown language $lang")
    LANG[] = lang
    persist && save_setting!("language", String(lang))
    return lang
end

"""
    L(text, args...) -> String

`text` (German) in the current language. Placeholders `{1}`, `{2}`, … are replaced by `args`.
"""
function L(text::AbstractString, args...)
    s = LANG[] == :en ? get(EN, text, text) : String(text)
    for (k, a) in enumerate(args)
        s = replace(s, "{$k}" => string(a))
    end
    return s
end

"Translates every option of a menu list (the code keeps working with indices or the German keys)."
Ls(xs) = [L(x) for x in xs]

"Registers English translations (German => English)."
function add_translations!(d::AbstractDict)
    merge!(EN, d)
    return EN
end
