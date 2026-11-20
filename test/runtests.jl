using Test, DrumMachine, WAV
using DrumMachine: NTRACKS, SR, step_samples, MAXSTEPS

@testset "DrumMachine" begin
    es = kit_entries([DrumMachine.KIT_DIR])           # package kits only, no user downloads
    @test any(e -> e.name == "BlackPearl", es)
    @test [e.name for e in es[end-1:end]] == ["808 (Synth)", "909 (Synth)"]
    syns = get_kit.(es[end-1:end])
    for k in syns
        y = render_song(preset("Pop: Disco"), k; repeats = 1)
        @test 0.2 < maximum(abs, y) < 0.98
    end
    bp = get_kit(only(filter(e -> e.name == "BlackPearl", es)))   # by name, not by sort position
    @test all(length(l) == 5 for l in bp.layers)
    t1, t2 = DrumMachine.track_index("Tom"), DrumMachine.track_index("Tom2")   # no tom 2 recorded:
    @test length(bp.layers[t2][3][1]) ≈ length(bp.layers[t1][3][1]) * 2^(3 / 12) rtol = 0.01   # tom 1, 3 semitones lower
    syn = syns[1]                         # 808 synth: one sample per level, deterministic, cheap

    @testset "Presets & Pattern-Text" begin
        for n in PRESET_NAMES
            s = preset(n)
            @test all(1 <= i <= length(s.patterns) for i in s.chain)
            @test all(p -> 1 <= p.steps <= MAXSTEPS, s.patterns)
            @test any(!iszero, s.patterns[1].grid) || n == "Leer"
            @test s.patterns[1].steps % s.steps_per_beat == 0 || n == "Taktart: 7/8 (2+2+3)"
        end
        @test length(PRESET_NAMES) == length(unique(PRESET_NAMES))
        ht = preset("Shuffle: Purdie Half-Time (16tel-Triolen)")
        @test ht.steps_per_beat == 6 && ht.patterns[1].steps == 24
        @test sum(step_samples(ht, k) for k in 0:23) ≈ 4 * 60 / 80 * SR   # swing does not affect triplets
        @test preset("Blues: Shuffle (12 Takte)").patterns[1].steps == 12
        p = pattern_from_rows(Dict("Snare" => "..o.X..x"))
        @test p.steps == 8
        @test row_string(p, 2) == "..o.X..x"
        q = pattern_from_rows(Dict("Snare" => "x.x.x.x.x.x"); steps = 4); q.steps = 12
        @test row_string(q, 2) == "x.x........."                 # text beyond `steps` dropped, no hidden notes
        @test parse_chain("1x3 2", 2) == [1, 1, 1, 2]
        @test parse_chain("1 5 2", 2) == [1, 2]
    end

    @testset "Fill" begin
        g = preset("Rock: 8tel").patterns[2]
        for st in eachindex(FILL_STYLES), spb in (4, 3)
            f = make_fill(g, spb, st)
            n = g.steps - max(0, fld(g.steps - FILL_STYLES[st][2] * spb, spb) * spb)   # span starts on a beat
            @test f.steps == g.steps
            @test f.grid[:, 1:g.steps-n] == g.grid[:, 1:g.steps-n]     # groove before it is kept
            @test any(!iszero, f.grid[:, g.steps-n+1:g.steps])
            @test f.grid[4, g.steps-n+1:g.steps] == zeros(UInt8, n)     # hi-hat rests during the fill
        end
        @test make_fill(g, 4, 1).grid == make_fill(g, 4, length(FILL_STYLES) + 1).grid
        @test row_string(make_fill(g, 4, 2), 7) == ".............x.."             # tom run-out: tom in the middle
        short = pattern_from_rows(Dict("Snare" => "X.X."))
        @test make_fill(short, 4, length(FILL_STYLES)).steps == 4                 # fill longer than pattern
        @test row_string(make_fill(preset("Taktart: 7/8 (2+2+3)").patterns[1], 4, 1), 2) == "..X...X.XxxxXX"   # odd meter: fill starts on a beat
    end

    @testset "Spur-Effekte" begin
        D = DrumMachine
        q = D.design!(D.Biquad(), :low, 120, 6)                 # +6 dB lows -> 50 Hz sine ~ twice as loud
        y = [D.process(q, Float32(sinpi(2 * 50 * k / SR)), 0f0)[1] for k in 1:SR]
        @test 1.8 < maximum(abs, y[SR÷2:end]) < 2.1
        q = D.design!(D.Biquad(), :high, 5000, 6)               # high shelf leaves bass unchanged
        y = [D.process(q, Float32(sinpi(2 * 50 * k / SR)), 0f0)[1] for k in 1:SR]
        @test 0.97 < maximum(abs, y[SR÷2:end]) < 1.03
        s = preset("Rock: 8tel")
        y0 = render_song(s, bp; repeats = 1)
        s2 = copy(s); s2.tracks[2].eq_midf = 2000                # only frequency changed: no effect
        @test render_song(s2, bp; repeats = 1) == y0             # exact equality: the export is reproducible
        D.set_mod!(s2.tracks[4], "Flanger"); s2.tracks[4].mod_mix = 1
        s2.tracks[1].eq_low = 4.5; D.set_mod!(s2.tracks[2], "Chorus")
        y1 = render_song(s2, bp; repeats = 1)
        @test y1 != y0 && maximum(abs, y1) < 0.98
        mktempdir() do dir
            path = joinpath(dir, "fx.toml")
            save_song(path, s2)
            txt = read(path, String)
            @test occursin("mod = \"Flanger\"", txt) && occursin("eq_low = 4.5", txt)
            @test count("eq_low", txt) == 1                       # only tracks with an effect
            t = load_song(path).tracks
            @test t[4].mod == 3 && t[4].mod_mix == 1 && t[4].mod_fb ≈ 0.75
            @test t[2].mod == 2 && t[1].eq_low == 4.5 && t[3].mod == 1
            @test render_song(load_song(path), bp; repeats = 1) ≈ y1
        end
    end

    @testset "Priorität" begin
        D = DrumMachine
        withenv("DRUMMACHINE_RT" => "70") do; @test D.rt_priority() == 70; end
        withenv("DRUMMACHINE_RT" => "500") do; @test D.rt_priority() == 99; end
        withenv("DRUMMACHINE_RT" => nothing) do; @test D.rt_priority() == 0; end
        D.set_thread_sched!(D.current_thread(), 1)                          # may fail without rights, must not throw
        @test D.set_thread_sched!(D.current_thread(), 0)
    end

    @testset "Tempo pro Pattern" begin
        D = DrumMachine
        a = pattern_from_rows(Dict("Kick" => "x...x...x...x...")); b = copy(a); b.bpm = 60
        s = Song(bpm = 120, patterns = [a, b], chain = [1, 2], countin = 0, repeats = 1)
        @test D.pattern_bpm(s, a) == 120 && D.pattern_bpm(s, b) == 60 && D.has_pattern_tempo(s)
        @test sum(step_samples(s, k, b) for k in 0:15) ≈ 4SR                 # 4 quarters at 60 BPM
        @test D.song_seconds(s) ≈ 2 + 4                                       # 120 BPM bar + 60 BPM bar
        s.countin = 1; s.chain = [2, 1]
        @test D.song_seconds(s) ≈ 4 + 4 + 2                                   # count-in at the first pattern's tempo
        s.countin = 0; s.chain = [1, 2]
        y = render_song(s, syn)
        @test size(y, 1) >= round(Int, 6SR)                                  # 2 s + 4 s (plus decay)
        mktempdir() do dir                                                   # saved only when set
            f = joinpath(dir, "t.toml"); save_song(f, s)
            l = load_song(f)
            @test [p.bpm for p in l.patterns] == [0.0, 60.0] && count("bpm =", read(f, String)) == 2
        end
        @test D.parse_pattern_bpm("") == 0 && D.parse_pattern_bpm("140,5") == 140.5
        @test D.parse_pattern_bpm("10") === nothing && D.parse_pattern_bpm("abc") === nothing
        @test make_fill(b, 4, 1).bpm == 60                                    # a fill keeps the tempo
        for v in (0.0, 60.0, 92.5, 140.25)                                    # field text parses back exactly
            q = Pattern(16); q.bpm = v
            @test D.parse_pattern_bpm(D.pattern_bpm_string(q)) == v
        end
    end

    @testset "Verzierungen" begin
        D = DrumMachine
        sn = D.track_index("Snare")
        p = pattern_from_rows(Dict("Snare" => "x...x...x...x..."))
        p.orn[sn, [1, 5, 9, 13]] .= [D.ORN_DOUBLE, D.ORN_BUZZ, D.ORN_FLAM, D.ORN_DRAG]
        p.orn[sn, 2] = D.ORN_FLAM                                   # no note there: does not count
        s = Song(bpm = 120, patterns = [p], countin = 0)
        @test D.orn_string(p, sn) == "2...z...f...r..."
        @test !haskey(D.pattern_to_dict(Pattern(16)), "orn")
        @test_throws Exception D.orn_from_char('q')
        q = make_fill(p, 4, 1)                                      # fill clears ornaments in its span
        @test all(iszero, q.orn[:, 13:16])
        # engine: the extra strokes of the first `n` steps (time, track, level, gain)
        function strokes(song, n)
            eng = D.Engine(song, syn)
            D.start_seq!(eng, [1], 0); eng.next_step_at = 0.0; empty!(eng.pending)
            evs = []
            for _ in 1:n
                eng.samplepos = floor(Int, eng.next_step_at)
                D.do_step!(eng)
                append!(evs, eng.pending); empty!(eng.pending)
            end
            return evs
        end
        evs = strokes(s, 16)
        d = step_samples(s, 0)
        n = clamp(round(Int, d / (s.orn.buzz_ms / 1000 * SR)), first(D.BUZZ_COUNT), last(D.BUZZ_COUNT))
        @test count(e -> e[1] ≈ d / 2 && e[3] == 2, evs) == 1                  # double stroke
        @test count(e -> 4d < e[1] < 5d, evs) == n - 1                         # buzz bounces
        @test count(e -> e[1] ≈ 8d - s.orn.flam_ms / 1000 * SR && e[3] == 1, evs) == 1   # flam grace note
        @test count(e -> any(g -> e[1] ≈ 12d - g * SR, D.grace_gaps(s.orn, D.ORN_DRAG)), evs) == 2  # drag
        @test length(evs) == 1 + (n - 1) + 1 + 2 && all(e -> e[2] == sn, evs)
        # timing per song: other flam distance, quieter grace notes; saved only when changed
        s.orn.flam_ms = 50; s.orn.grace = 0.5
        fl = only(filter(e -> 7d < e[1] < 8d, strokes(s, 8)))
        @test fl[1] ≈ 8d - 0.05SR && fl[4] ≈ 0.5 * D.FLAM_GAIN
        @test D.song_to_dict(s)["ornaments"] == Dict("flam_ms" => 50.0, "grace" => 0.5)
        @test !haskey(D.song_to_dict(Song()), "ornaments")
        mktempdir() do dir                                          # TOML round trip: ornaments and timing
            f = joinpath(dir, "t.toml"); save_song(f, s)
            @test occursin("pattern.orn", read(f, String))
            l = load_song(f); o = l.orn
            @test D.orn_string(l.patterns[1], sn) == "2...z...f...r..."
            @test o.flam_ms == 50 && o.grace == 0.5 && o.drag_ms == D.OrnTuning().drag_ms
        end
        @test D.orn_tuning_from_dict(Dict("buzz_ms" => 1000)).buzz_ms == 40      # clamped
        s.orn = D.OrnTuning()
        # rendered: same length as without ornaments, but more strokes
        plain = copy(s); fill!(plain.patterns[1].orn, 0x00)
        y = render_song(s, syn; repeats = 1); y0 = render_song(plain, syn; repeats = 1)
        @test size(y) == size(y0) && y != y0
        # 32nd grid: double stroke on step 1 sits on the half step
        z = Song(bpm = 104, steps_per_beat = 8, patterns = [pattern_from_rows(Dict("Snare" => "x"); steps = 32)])
        z.patterns[1].orn[sn, 1] = D.ORN_DOUBLE
        @test only(strokes(z, 1))[1] ≈ step_samples(z, 0) / 2
        # drag in a fast grid: grace notes squeezed into the previous step, order kept
        z.patterns[1] = pattern_from_rows(Dict("Snare" => ".x"); steps = 32)
        z.patterns[1].orn[sn, 2] = D.ORN_DRAG
        g = sort(first.(strokes(z, 1))); d1 = step_samples(z, 0)
        @test length(g) == 2 && 0 < g[1] < g[2] < d1 && g[2] - g[1] ≈ d1 - g[2]
        # dry run: a double on the last step keeps its second stroke after the end of the sequence
        e = Song(); e.chain = [1]; e.patterns[1].grid[2, 16] = 2; e.patterns[1].orn[2, 16] = D.ORN_DOUBLE
        @test [(h[1], h[4]) for h in D.song_hits(e; repeats = 1, countin = 0, click = false)[1]] == [(99225, 1f0), (102533, 0.92f0)]
        # flam on step 1: a 16th pickup before the main hit (as in the MIDI file), in a loop it closes the bar
        e = Song(); e.chain = [1]; e.patterns[1].grid[2, 1] = 2; e.patterns[1].orn[2, 1] = D.ORN_FLAM
        sh = round(Int, e.orn.flam_ms / 1000 * SR); P = round(Int, 60 / e.bpm * SR / 4)
        @test [(h[1], h[4]) for h in D.song_hits(e; repeats = 1, countin = 0, click = false)[1]] == [(P - sh, 0.9f0), (P, 1f0)]
        h, _, tot = D.song_hits(e; repeats = 1, countin = 0, click = false, loop = true)
        @test [(x[1], x[4]) for x in h] == [(round(Int, tot) - sh, 0.9f0), (0, 1f0)]
    end

    @testset "L/R pro Spur" begin
        D = DrumMachine
        eng = D.Engine(Song(), syn)
        st = D.Sample(Float32[1, 1, 1], Float32[0, 0, 0])               # stereo: left only
        v = D.start_voice!(eng, st, 1f0, 0.5f0, 1.0, 1, 0; swap = true)
        @test v.buf === st.r && v.bufr === st.l && v.gl > v.gr          # channels swapped, pan mirrored
        mo = D.Sample(Float32[1, 1, 1])
        a = D.start_voice!(eng, mo, 1f0, 0.6f0, 1.0, 1, 0)
        b = D.start_voice!(eng, mo, 1f0, 0.6f0, 1.0, 1, 0; swap = true)
        @test a.gl ≈ b.gr && a.gr ≈ b.gl && a.gr > a.gl                  # mono: mirrored position
        s = preset("Rock: 8tel"); s.fx = "Clean"; s.tracks[4].pan = -1  # hi-hat hard left
        y = render_song(s, syn; repeats = 1)
        for tp in s.tracks; tp.swap = true; end
        yt = render_song(s, syn; repeats = 1)
        s.swap_lr = true; for tp in s.tracks; tp.swap = false; end
        z = render_song(s, syn; repeats = 1)
        @test z[:, 1] == y[:, 2] && z[:, 2] == y[:, 1]                   # global swap exchanges the channels
        @test yt ≈ z                                                     # all tracks swapped = global swap
        mktempdir() do dir
            s.tracks[D.track_index("Crash")].swap = true
            f = joinpath(dir, "s.toml"); save_song(f, s)
            l = load_song(f)
            @test l.swap_lr && l.tracks[D.track_index("Crash")].swap && !l.tracks[D.track_index("Kick")].swap
            @test count("swap_lr", read(f, String)) == 2                 # song-wide + Crash only
        end
    end

    @testset "Setup-Player" begin
        D = DrumMachine
        mktempdir() do dir
            # setup file round trip
            sl = D.Setlist("Gig")
            push!(sl.entries, D.SetEntry(joinpath(dir, "a.toml"); pause = 2.5, beep = true), D.SetEntry("b.wav"))
            f = D.save_setlist(joinpath(dir, "gig.toml"), sl)
            l = D.load_setlist(f)
            @test l.name == "Gig" && length(l.entries) == 2
            @test l.entries[1].pause == 2.5 && l.entries[1].beep && !l.entries[2].beep
            @test D.entry_file(l.entries[2]) == joinpath(D.song_dir(), "b.wav")      # relative to the song folder
            # preparing: song rendered with its kit, WAV resampled to stereo at SR
            s = preset("Rock: 8tel"); s.kit = "808 (Synth)"; s.repeats = 1; s.countin = 1; s.name = "Probe"
            save_song(joinpath(dir, "a.toml"), s)
            y, cue = D.prepare_entry_cue(D.SetEntry(joinpath(dir, "a.toml")))
            @test size(y, 2) == 2 && isapprox(size(y, 1), D.song_seconds(s) * SR; rtol = 0.1)
            @test cue > 0 && isapprox(cue, (D.song_seconds(s) - D.song_seconds(s; countin = 0)) * SR; atol = 2)   # count-in
            @test D.entry_title(D.SetEntry(joinpath(dir, "a.toml"))) == "Probe"
            save_wave(joinpath(dir, "m.wav"), Wave(fill(0.25f0, 22050), 22050))
            w, wc = D.prepare_entry_cue(D.SetEntry(joinpath(dir, "m.wav")))
            @test size(w) == (SR, 2) && wc == 0 && D.entry_title(D.SetEntry(joinpath(dir, "m.wav"))) == "m"
            @test_throws Exception D.prepare_entry_cue(D.SetEntry(joinpath(dir, "fehlt.toml")))
            # a MIDI file plays as silence of its length, its events go out at their frames
            mf = export_midi(joinpath(dir, "Groove.mid"), s; repeats = 1, countin = 0)
            my, mc, (fr, ms, ch) = D.prepare_entry_cue(D.SetEntry(mf))
            @test size(my, 1) == round(Int, D.read_midi_file(mf).length * SR) && all(iszero, my) && mc == 0
            @test issorted(fr) && length(fr) == length(ms) && fr[1] == 1 && ch == 0x0200    # channel 10
            @test D.entry_title(D.SetEntry(mf)) == "Groove"
            # loop exports are refused, loop songs are rendered once (with count-in, not folded)
            @test D.is_loop_file("x/Rock 8tel Loop.wav") && D.is_loop_file("a_loop.WAV") && !D.is_loop_file("Looping.wav")
            save_wave(joinpath(dir, "m Loop.wav"), Wave(fill(0.25f0, 100), 22050))
            @test_throws Exception D.prepare_entry_cue(D.SetEntry(joinpath(dir, "m Loop.wav")))
            s.loop = true; save_song(joinpath(dir, "l.toml"), s)
            @test size(first(D.prepare_entry_cue(D.SetEntry(joinpath(dir, "l.toml")))), 1) > D.song_seconds(s; countin = 0) * SR
        end
        # reloaded setup keeps pause/beep by path, a song twice is matched first to first
        a = D.Setlist("x", [D.SetEntry("s1"), D.SetEntry("s2"), D.SetEntry("s1")])
        o = D.Setlist("x", [D.SetEntry("s1"; pause = 3), D.SetEntry("s1"; pause = 5, beep = true)])
        D.keep_pause_beep!(a, o)
        @test [(e.pause, e.beep) for e in a.entries] == [(3.0, false), (0.0, false), (5.0, true)]
        # playback: auto continues after the pause (with beeps), manual stops after the song
        pl = D.Player()
        a = fill(0.1f0, 1000, 2); b = fill(-0.1f0, 1000, 2)
        pl.items = [a, b]; pl.cues = [0, 0]; pl.delays = [0.0, 3.5]; pl.beeps = [false, true]
        D.player_start!(pl, 1; pause = true)
        @test pl.state == 2                                       # no pause before the first song
        out = zeros(Float32, 1000 + round(Int, 3.5SR) + 500, 2)
        D.mix_player!(pl, out)
        @test all(out[1:1000, 1] .≈ 0.1f0)
        beep_at = findall(k -> abs(out[k, 1]) > 0.05, 1001:1000+round(Int, 3.5SR)) .+ 1000
        @test !isempty(beep_at) && minimum(beep_at) >= 1000 + round(Int, 0.5SR)   # beeps in the last 3 s only
        @test pl.state == 2 && pl.cur == 2
        D.mix_player!(pl, zeros(Float32, 2000, 2))
        @test pl.state == 0 && pl.tail > 0                        # end of the setup, reverb tail
        pl.auto = false
        D.player_start!(pl, 1; pause = false)
        D.mix_player!(pl, zeros(Float32, 1500, 2))
        @test pl.state == 0 && pl.cur == 1                        # manual: no next song
        D.player_start!(pl, 2; pause = false); D.player_stop!(pl)
        @test !D.player_active(pl)
        # beeps off: the pause runs silently
        pl.auto = true; pl.beepgain = 0f0
        D.player_start!(pl, 2; pause = true)
        q = zeros(Float32, round(Int, 3.5SR), 2); D.mix_player!(pl, q)
        @test all(iszero, q) && pl.state == 2
        D.player_stop!(pl); pl.beepgain = 1f0
        # routing: music mono left, beeps alone right
        pl.route = 2; pl.auto = true
        D.player_start!(pl, 2; pause = true)
        q = zeros(Float32, round(Int, 3.5SR) + 100, 2); D.mix_player!(pl, q)
        @test maximum(abs, q[1:round(Int, 3.5SR), 1]) == 0 && maximum(abs, q[1:round(Int, 3.5SR), 2]) > 0.1
        @test all(q[end-50:end, 2] .== 0) && all(q[end-50:end, 1] .≈ -0.1f0 * 0.7071f0 * 2)
        # the count-in at the start of a song is a cue as well: right channel only
        pl.cues = [200, 0]; pl.auto = false; D.player_start!(pl, 1; pause = false)
        q = zeros(Float32, 400, 2); D.mix_player!(pl, q)
        @test all(iszero, q[1:199, 1]) && all(q[1:199, 2] .≈ 0.1f0) && all(q[202:400, 2] .== 0) && q[300, 1] ≈ 0.1f0 * 0.7071f0 * 2
        pl.cues = [0, 0]
        D.player_stop!(pl); pl.route = 1
        # master: volume and soft limit
        pl.gain = 0.5f0; pl.auto = false; D.player_start!(pl, 1; pause = false)
        o = zeros(Float32, 10, 2); D.mix_player!(pl, o)
        @test o[1, 1] ≈ 0.05f0
        @test D.softclip(3f0) <= 1f0 && D.softclip(0.5f0) == 0.5f0 && D.softclip(-0.9f0) > -0.9f0
        # in the engine: the player is mixed into the output
        eng = Engine(Song(), syn)
        eng.player.items = [a]; eng.player.cues = [0]; eng.player.delays = [0.0]; eng.player.beeps = [false]
        D.player_start!(eng.player, 1; pause = false)
        @test D.render!(eng, zeros(Float32, D.BLOCK, 2))[1, 1] ≈ 0.1f0
        eng.song.bpm = 90; D.render!(eng, zeros(Float32, D.BLOCK, 2))
        @test eng.fx.echo.delay == D.echo_delay(90, SR)                 # master echo follows the tempo
        push!(eng.pending, (1e9, 2, 2, 1f0)); D.stop!(eng)
        @test isempty(eng.pending)                                      # no ornament strokes after stop
    end

    @testset "Loop-Export" begin
        D = DrumMachine
        s = preset("Rock: 8tel"); s.chain = [2]; s.fx = "Hall"; s.fxmix = 0.5; s.master = 0.3
        p = s.patterns[2]; p.grid[2, 1] = 2; p.orn[2, 1] = D.ORN_FLAM   # grace note before the loop point
        L = render_song(s, syn; repeats = 1, loop = true)
        @test size(L, 1) == round(Int, D.song_seconds(s; repeats = 1, countin = 0) * SR)
        y = render_song(s, syn; repeats = 3, countin = 0)          # played through: middle bar = loop
        n = size(L, 1); sh = round(Int, 60 / D.pattern_bpm(s, p) * SR / 4)   # file starts with a 16th pickup
        @test maximum(abs, L .- y[sh+n+1:sh+2n, :]) < 1e-3
        s.loop = true
        @test D.song_seconds(s) ≈ D.song_seconds(s; countin = 0)   # count-in is dropped
        mktempdir() do dir
            p = export_wav(joinpath(dir, "loop.wav"), s, syn; repeats = 1)
            b = read(p)
            @test ltoh(reinterpret(UInt32, b[5:8])[1]) == length(b) - 8   # RIFF size is correct
            @test findfirst(b"smpl", b) === nothing                 # plain WAV, TD-27 rejects extra metadata
            w, fs = WAV.wavread(p)
            @test D.td27_name_warning(joinpath(dir, "Rock 8tel Loop.wav")) == ""
            @test occursin("16", D.td27_name_warning(joinpath(dir, "Funk Ghost Notes Loop.wav")))
            @test occursin("_Click", D.td27_name_warning(joinpath(dir, "Groove_Click.wav")))
            @test size(w, 1) == n && fs == SR                         # file stays readable
            save_song(joinpath(dir, "s.toml"), s)
            @test load_song(joinpath(dir, "s.toml")).loop
        end
    end

    @testset "WAV-Editor" begin
        D = DrumMachine
        fs = 44100
        x = Float32.(0.5 .* sinpi.(2 * 440 .* (0:fs-1) ./ fs))
        w = Wave(hcat(x, -x), fs)
        v = copy(w); D.delete_range!(v, 1:100); @test D.nframes(v) == fs - 100
        v = copy(w); D.crop!(v, 101:200); @test D.nframes(v) == 100 && v.data[1, 1] == w.data[101, 1]
        v = copy(w); D.silence!(v, 1:50); @test all(iszero, v.data[1:50, :]) && v.data[51, 1] == w.data[51, 1]
        v = copy(w); D.fade_in!(v, 1:1); @test v.data[1, 1] == w.data[1, 1]         # 1-sample fade (SEdit threw)
        v = copy(w); D.fade_in!(v, 1:1000; curve = :linear)
        @test v.data[1, 1] == 0 && v.data[1000, 1] == w.data[1000, 1]
        v = copy(w); D.fade_out!(v, fs-999:fs); @test v.data[end, 1] == 0
        v = copy(w); D.normalize!(v, 1:fs; peak_db = 0); @test maximum(abs, v.data) ≈ 1
        v = copy(w); D.gain!(v, 1:fs, -6.0206); @test maximum(abs, v.data) ≈ 0.25 atol = 1e-3
        v = copy(w); D.reverse!(v, 1:fs); @test v.data[1, :] == w.data[end, :]
        v = copy(w); D.insert_silence!(v, 1, 0.5); @test D.nframes(v) == fs + fs ÷ 2 && all(iszero, v.data[1:fs÷2, :])
        v = copy(w); D.prepend_countin!(v; bpm = 120, beats = 4)
        @test D.nframes(v) - fs == 4 * round(Int, 60fs / 120)                       # whole beats (SEdit: one short)
        v = copy(w); c = D.copy_range(v, 1:10); D.paste!(v, 1, c); @test D.nframes(v) == fs + 10
        m = Wave(x, fs); D.paste!(m, 1, hcat(x[1:5], x[1:5])); @test D.nchan(m) == 1 && D.nframes(m) == fs + 5
        v = copy(w); D.set_channels!(v, 1); @test D.nchan(v) == 1
        @test_throws ErrorException D.delete_range!(copy(w), nothing)
        @test_throws ErrorException D.crop!(copy(w), 5:4)
        wi = Wave(hcat(x, x), fs)          # in phase: reverb/echo take the L+R sum as input
        for fx in D.WAVE_FX
            v = copy(wi); D.apply_fx!(v, 1:fs, fx; mix = 0.6, eq = (6, -3, 800, 2))
            @test all(isfinite, v.data)
            fx in ("Hall", "Room", "Echo") && @test D.nframes(v) > fs               # tail added at the end
        end
        v = copy(wi); D.apply_fx!(v, 1:fs÷2, "Hall"); @test D.nframes(v) == fs    # tail rings into the rest
        h = D.History(2); v = copy(w)
        for k in 1:3; D.snapshot!(h, v, "Schritt $k"); D.delete_range!(v, 1:10); end
        @test length(h.undo) == 2                                                   # limit
        hb = D.History(30; maxbytes = 1200)                                         # byte limit: 3 × 400 bytes
        for k in 1:5; D.snapshot!(hb, zeros(Float32, 100, 1), "s$k"); end
        @test length(hb.undo) == 3 && last(hb.undo)[2] == "s5"
        hb = D.History(30; maxbytes = 10); D.snapshot!(hb, zeros(Float32, 100, 1), "big")
        @test length(hb.undo) == 1                                                  # newest step always kept
        @test D.fmt_secs(65.0) == "1:05.000" && D.fmt_secs(119.9996) == "2:00.000"
        @test (D.fmt_time(59.7), D.fmt_time(119.6), D.fmt_time(61)) == ("1:00", "2:00", "1:01")
        @test D.undo!(h, v) == "Schritt 3" && D.nframes(v) == fs - 20
        @test D.redo!(h, v) == "Schritt 3" && D.nframes(v) == fs - 30
        mn, mx = D.wave_peaks(w, 1, 1, fs, 500); @test length(mn) == 500 && isapprox(maximum(mx), 0.5; atol = 1e-3)
        mn, mx = D.wave_peaks(w, 1, 1, 10, 500); @test length(mn) == 10           # zoomed in: one bin per frame
        clk = zeros(Float32, 8fs); for b in 0:15; i = b * round(Int, 0.5fs) + 1; clk[i:i+400] .= 0.8f0; end
        @test D.estimate_bpm(Wave(clk, fs)) == 120
        s = preset("Rock: 8tel"); s.fx = "Clean"
        @test D.estimate_bpm(Wave(render_song(s, bp; repeats = 2, countin = 0), SR)) == 100
        mktempdir() do dir
            p = joinpath(dir, "t.wav")
            v = copy(w); D.gain!(v, 1:fs, 12)                                       # beyond full scale
            for bits in (16, 24, 32)
                save_wave(p, v; bits)
                r = load_wave(p)
                @test r.bits == bits && D.nframes(r) == fs && D.nchan(r) == 2
                bits < 32 && @test maximum(abs, r.data) <= 1                        # clamped, no InexactError
            end
            save_wave(p, w; range = 1:100); @test D.nframes(load_wave(p)) == 100
        end
        eng = Engine(preset("Rock: 8tel"), bp)                                      # playback via the engine
        D.preview_play!(eng, w.data, fs; from = 1, to = 1000, loop = true)
        buf = zeros(Float32, 512, 2)
        for _ in 1:6; D.render!(eng, buf); end
        @test eng.preview.on && 1 <= eng.preview.shown[] <= 1001 && maximum(abs, buf) > 0.1
        D.preview_play!(eng, w.data, fs; from = 1, to = 600)
        for _ in 1:3; D.render!(eng, buf); end
        @test !eng.preview.on
        # --- regressions from the review ---
        for bpm in (60, 90, 120, 140), rate in (22050, 44100, 48000)       # never negative / nonsense
            c = zeros(Float32, 12rate); per = round(Int, 60rate / bpm)
            for i in 1:per:length(c)-1000; c[i:i+round(Int, 0.02rate)] .= 0.8f0; end
            b = D.estimate_bpm(Wave(c, rate))
            @test b === nothing || 55 <= b <= 220
        end
        for rate in (22050, 96000)                                          # EQ at the file's own rate
            t = Float32.(0.1 .* sinpi.(2 * 800 .* (0:rate-1) ./ rate))
            v = Wave(t, rate); D.apply_fx!(v, 1:rate, "EQ"; eq = (0, 12, 800, 0))
            g = 20log10(maximum(abs, v.data[rate÷2:end, 1]) / 0.1)
            @test 11 < g < 13
        end
        v = Wave(x, 48000); c = D.copy_range(v, 1:48000)                   # clipboard keeps the rate
        u = Wave(x, fs); D.paste!(u, 1, c; fs = 48000); @test abs(D.nframes(u) - (fs + fs * fs / 48000)) <= 2
        v = Wave(Float32[1 2 3; 4 5 6], fs); D.set_channels!(v, 2); @test v.data == Float32[2 2; 5 5]
        mktempdir() do dir                                                   # formats and channels on load
            p8 = joinpath(dir, "8.wav"); WAV.wavwrite(hcat(x, x), p8; Fs = fs, nbits = 8, compression = WAV.WAVE_FORMAT_PCM)
            @test load_wave(p8).bits == 16
            p3 = joinpath(dir, "3.wav"); WAV.wavwrite(hcat(x, x, x), p3; Fs = fs, nbits = 16, compression = WAV.WAVE_FORMAT_PCM)
            @test D.nchan(load_wave(p3)) == 2
        end
        d96 = rand(Float32, 1000, 2)                                         # short loop at 96 kHz: no OOB
        D.preview_play!(eng, d96, 96000; from = 999, to = 1000, loop = true)
        for _ in 1:4; D.render!(eng, buf); end
        @test eng.preview.on && 999 <= eng.preview.shown[] <= 1001
        @test D.layout_char(D.GLMakie.Keyboard.z) in ('z', 'y')             # QWERTZ-aware shortcut letter
        docs = D.load_docs()                                                        # docs viewer finds docs/
        @test !isempty(docs) && all(p -> !isempty(p[2]), docs[1][3])
        @test all(length(split(p[2], '\n')) <= D.DOC_LINES for d in docs for p in d[3])  # pages fit the window
        mktempdir() do dir                                                          # stub: still one page
            f = joinpath(dir, "t.md"); write(f, "# T\n")
            @test D.doc_pages(f) == ("T", [("Overview", "")])
        end
        @test D.split_lines(join(["intro", "", join(["  row $k\n      text" for k in 1:30], '\n')], '\n'), 40) ==
              [join(["intro", "", join(["  row $k\n      text" for k in 1:19], '\n')], '\n'),
               join(["  row $k\n      text" for k in 20:30], '\n')]                   # long table: cut at a row
    end

    @testset "Sprache" begin
        D = DrumMachine
        @test D.locale_lang(Dict("LANG" => "de_DE.UTF-8")) == :de
        @test D.locale_lang(Dict("LANG" => "en_US.UTF-8")) == :en
        @test D.locale_lang(Dict("LC_ALL" => "de_AT.UTF-8", "LANG" => "en_US.UTF-8")) == :de   # LC_ALL wins
        @test D.locale_lang(Dict("LANG" => "C")) == :en
        @test D.locale_lang(Dict{String,String}()) == :en
        old = D.LANG[]
        try
            D.set_lang!(:en)
            @test D.L("Speichern") == "Save"
            @test D.L("Unbekannte Spur {1} ignoriert", "Cowbell") == "Unknown track Cowbell ignored"
            @test D.L("kein Eintrag {1}", 7) == "kein Eintrag 7"                 # fallback: German text
            D.set_lang!(:de)
            @test D.L("Speichern") == "Speichern"
        finally
            D.set_lang!(old)
        end
        mktempdir() do dir                                                      # stored choice wins
            withenv("XDG_CONFIG_HOME" => dir, "LANG" => "de_DE.UTF-8", "LC_ALL" => nothing, "LC_MESSAGES" => nothing) do
                @test D.initial_lang() == :de
                D.save_setting!("language", "en")
                @test D.initial_lang() == :en
            end
        end
        # every L("…") key has an English entry, no German UI text outside L()
        # (run in this process: a second Julia process would cost ~3 s)
        m = Module(); Core.eval(m, :(const ARGS = String[]))
        @test redirect_stdout(devnull) do
            Base.include(m, joinpath(pkgdir(DrumMachine), "tools", "check_i18n.jl"))
        end == (0, 0)
    end

    @testset "AAC" begin
        D = DrumMachine
        if D.has_ffmpeg()
            mktempdir() do dir
                fs = 44100
                x = Float32.(0.3 .* sinpi.(2 * 440 .* (0:2fs-1) ./ fs))
                p = D.save_aac(joinpath(dir, "t.m4a"), Wave(hcat(x, x), fs); range = 1:fs)
                @test filesize(p) > 1000
                info = read(`$(D.FFMPEG_jll.ffprobe()) -v error -show_entries stream=codec_name,channels -of csv=p=0 $p`, String)
                @test strip(info) == "aac,2"
            end
        else
            @test_skip "FFMPEG_jll not available on this platform"
        end
    end

    @testset "Kits laden" begin
        D = DrumMachine
        mktempdir() do dir
            # fake extracted CrocellKit mix: a few hits per instrument at 48 kHz
            src = joinpath(dir, "CrocellKit_Stereo_MIX")
            for (_, insts) in D.CROCELL_MAP, inst in insts
                mkpath(joinpath(src, inst, "samples"))
                for (k, a) in enumerate((0.05, 0.1, 0.2, 0.4, 0.8))
                    y = a .* exp.(-(0:4799) ./ 800) .* sinpi.(2 .* 200 .* (0:4799) ./ 48000)
                    WAV.wavwrite(hcat(y, y), joinpath(src, inst, "samples", "hit$k.wav"); Fs = 48000, nbits = 16, compression = WAV.WAVE_FORMAT_PCM)
                end
            end
            msgs = String[]
            dest = joinpath(dir, "kits", "CrocellKit")
            D.build_crocell(; src, dest, log = m -> push!(msgs, m))
            @test isfile(joinpath(dest, "kit.toml")) && isfile(joinpath(dest, "LICENSE.txt"))
            @test !isdir(dest * ".building")                                   # built atomically
            mkpath(dest * ".building"); cp(joinpath(dest, "kit.toml"), joinpath(dest * ".building", "kit.toml"))   # interrupted rebuild
            @test_throws ErrorException D.build_kit(joinpath(dir, "Z"), "Z", ["Kick" => [() -> error("x")]];
                                                    header = "", license = "", log = _ -> nothing)
            @test !isdir(joinpath(dir, "Z.building")) && !isdir(joinpath(dir, "Z"))   # failed build leaves nothing
            @test any(occursin("12/12", m) for m in msgs) && occursin("CrocellKit", msgs[end])
            withenv("DRUMMACHINE_KIT_DIR" => joinpath(dir, "kits")) do      # found in the user kit dir
                @test joinpath(dir, "kits") in D.kit_dirs()
                # listing reads no samples; a kit is loaded once and then taken from the cache
                es = kit_entries([joinpath(dir, "kits")])
                @test [e.name for e in es] == ["CrocellKit", "808 (Synth)", "909 (Synth)"]   # .building ignored
                k1 = get_kit(es[1]); @test get_kit(es[1]) === k1
                @test k1.name == "CrocellKit" && all(length(l) == 5 for l in k1.layers)
                touch(joinpath(dest, "kit.toml")); sleep(0.01)
                @test get_kit(es[1]) !== k1                                     # kit.toml changed
                write(joinpath(dest, "kit.toml"), "name = [")                   # broken file
                k3 = @test_logs (:warn,) match_mode = :any get_kit(es[1])
                @test k3.name == "CrocellKit" && length(k3.layers[1]) == 1     # synth fallback
            end
            # download with progress (file:// URL instead of the 561 MB archive)
            blob = joinpath(dir, "blob.bin"); write(blob, rand(UInt8, 3_000_000))
            got = D.fetch_file("file://" * blob, joinpath(dir, "cache", "blob.bin"), "Test"; log = m -> push!(msgs, m))
            @test read(got) == read(blob) && !isfile(got * ".part")
            # unpacking with bsdtar from LibArchive_jll (zip made by bsdtar itself)
            zip = joinpath(dir, "t.zip")
            cd(() -> Base.run(`$(D.bsdtar()) -a -cf $zip blob.bin`), dir)
            mkpath(joinpath(dir, "x")); touch(joinpath(dir, "x", "extra"))
            @test read(joinpath(D.extract(zip, joinpath(dir, "x"), ["blob.bin"]), "blob.bin")) == read(blob)
            @test isfile(joinpath(dir, "x", "extra"))                          # merged into the folder
            bad = joinpath(dir, "bad.zip"); write(bad, "no zip")
            @test_throws Exception D.extract(bad, joinpath(dir, "y"))
            @test isempty(readdir(joinpath(dir, "y")))                         # nothing half-written left
            # lock file across processes: held by a running process -> not run; stale -> taken over
            lk = joinpath(dir, "k.lock"); write(lk, "1")
            @test D.with_pidlock(() -> nothing, lk) == false
            write(lk, "4194305")                                                # above any pid_max
            @test D.with_pidlock(() -> nothing, lk) == true && !isfile(lk)
            # automatic download only with auto_kits = true, never with DRUMMACHINE_NO_KIT_DOWNLOAD
            withenv("XDG_CONFIG_HOME" => joinpath(dir, "cfg"), "XDG_CACHE_HOME" => joinpath(dir, "cache"),
                    "DRUMMACHINE_NO_KIT_DOWNLOAD" => nothing) do
                calls = String[]                                                # failed build: done called, not building
                ok = @test_logs (:warn,) match_mode = :any D.fetch_kit(("T", "1 MB", (; log) -> error("net"), true, ["T"]),
                                                                        _ -> nothing, n -> push!(calls, n))
                @test ok && calls == ["T"] && !D.kit_building("T")
                @test !D.auto_kits_enabled()                                    # default: off
                @test length(D.on_demand_kits()) == length(D.missing_kits())   # all in the kit menu
                D.save_setting!("auto_kits", true)
                @test D.auto_kits_enabled()
                withenv("DRUMMACHINE_NO_KIT_DOWNLOAD" => "1") do
                    @test !D.auto_kits_enabled() && D.auto_fetch_kits!(println, println) === nothing
                end
            end
        end
    end

    @testset "Song-Ordner" begin
        D = DrumMachine
        @test !D.songs_writable(joinpath(DEPOT_PATH[1], "packages", "DrumMachine", "AbCd1", "songs"))   # Pkg install
        mktempdir() do dir
            withenv("DRUMMACHINE_SONG_DIR" => nothing, "XDG_CONFIG_HOME" => joinpath(dir, "cfg")) do
                # git checkout: songs/ as before; Pkg install: data dir
                @test D.song_dir() == (D.songs_writable(D.SONG_DIR) ? D.SONG_DIR : joinpath(D.data_dir(), "songs"))
                D.save_setting!("song_dir", joinpath(dir, "mine"))          # own folder from the settings
                @test D.song_dir() == joinpath(dir, "mine") && isdir(D.song_dir())
                withenv(() -> @test(D.song_dir() == joinpath(dir, "own")), "DRUMMACHINE_SONG_DIR" => joinpath(dir, "own"))
            end
            withenv("DRUMMACHINE_SONG_DIR" => joinpath(dir, "own")) do   # e.g. installed read-only
                @test D.song_dir() == joinpath(dir, "own") && isdir(D.song_dir())
                save_song(joinpath(D.song_dir(), "Mein Groove.toml"), preset("Rock: 8tel"))
                names = D.list_songs()
                @test "Mein Groove" in names && "Rock 8tel" in names   # own songs + examples
                @test D.song_file("Rock 8tel") == joinpath(D.SONG_DIR, "Rock 8tel.toml")
                @test D.song_file("Mein Groove") == joinpath(dir, "own", "Mein Groove.toml")
            end
            # layout of Pkg: folder writable, shipped files read-only
            ro = joinpath(dir, "ro"); mkpath(ro); f = joinpath(ro, "a.toml"); write(f, "x")
            @test D.songs_writable(ro)
            chmod(f, 0o444)
            @test !D.songs_writable(ro) || Sys.iswindows() || get(ENV, "USER", "") == "root"
            chmod(f, 0o644)
        end
    end

    @testset "Datei-Dialog" begin
        mktempdir() do bin                                # fake zenity and kdialog: never a real dialog
            fake = joinpath(bin, "zenity"); kd = joinpath(bin, "kdialog")
            write(fake, "#!/bin/sh\necho /x/y.toml\n"); write(kd, "#!/bin/sh\necho /k/z.toml\n")
            chmod(fake, 0o755); chmod(kd, 0o755)
            withenv("PATH" => bin * ":" * ENV["PATH"], "XDG_CURRENT_DESKTOP" => nothing) do
                @test DrumMachine.pick_song_file() == "/x/y.toml"
                write(fake, "#!/bin/sh\nexit 1\n")
                @test DrumMachine.pick_song_file() == ""                  # cancel
            end
            withenv("PATH" => bin * ":" * ENV["PATH"], "XDG_CURRENT_DESKTOP" => "KDE") do   # KDE: kdialog first
                @test DrumMachine.dialog_prog() == "kdialog" && DrumMachine.pick_song_file() == "/k/z.toml"
            end
        end
    end

    @testset "Timing" begin
        s = preset("Rock: 16tel"); s.bpm = 120
        @test sum(step_samples(s, k) for k in 0:15) ≈ 2SR      # 4 quarters at 0.5 s
        s.swing = 0.66
        @test step_samples(s, 0) > step_samples(s, 1)
        @test sum(step_samples(s, k) for k in 0:15) ≈ 2SR      # swing does not change the bar length
        # Auto: 8th groove swings on 8ths, 16th groove on 16ths
        p8 = pattern_from_rows(Dict("HiHat" => "x.x.x.x.x.x.x.x."))
        p16 = pattern_from_rows(Dict("HiHat" => "xxxxxxxxxxxxxxxx"))
        on8 = cumsum([step_samples(s, k, p8) for k in 0:15])
        @test on8[2] / (on8[4] - on8[2]) ≈ 0.66 / 0.34          # "+" moves later
        @test step_samples(s, 0, p16) > step_samples(s, 1, p16)
        s.swing_on = 8
        @test step_samples(s, 0, p16) == step_samples(s, 1, p16)
        @test sum(step_samples(s, k, p16) for k in 0:15) ≈ 2SR
        # odd step count: the incomplete swing pair plays straight, the bar keeps its length
        base = 60 / 120 / 4 * SR; s.swing = 2 / 3
        @test sum(step_samples(s, k, Pattern(14)) for k in 0:13) ≈ 14base
        s.swing_on = 16
        @test sum(step_samples(s, k, Pattern(7)) for k in 0:6) ≈ 7base
        # triplet grid: default = exact triplets, swing shifts the third triplet
        t = Song(bpm = 120, steps_per_beat = 3)
        @test t.swing == 2 / 3
        @test step_samples(t, 0) ≈ step_samples(t, 1) ≈ step_samples(t, 2)
        t.swing = 0.75
        @test step_samples(t, 0) + step_samples(t, 1) ≈ 0.75 * 0.5SR
        @test sum(step_samples(t, k) for k in 0:11) ≈ 2SR
        t.swing = 0.6
        @test sum(step_samples(t, k, Pattern(10)) for k in 0:9) ≈ 10 * 0.5SR / 3    # incomplete triplet group
        # 32nd grid: 8 steps per beat, swing on 16ths moves the second 16th (steps 3–4) later
        z = Song(bpm = 120, steps_per_beat = 8, swing_on = 16)
        z.swing = 0.6
        @test step_samples(z, 0) == step_samples(z, 1) > step_samples(z, 2) == step_samples(z, 3)
        @test step_samples(z, 0) + step_samples(z, 1) ≈ 0.6 * 0.25SR
        @test sum(step_samples(z, k) for k in 0:31) ≈ 2SR
        # Human: 0 = exact grid; 1 = each hit at most ±10 ms and ±3 dB off, early and late
        h = preset("Rock: 16tel"); h.bpm = 120
        bytrack(x) = sort(x[1]; by = e -> (e[2], e[1]))
        exact = bytrack(DrumMachine.song_hits(h; repeats = 1, countin = 0, click = false))
        h.human = 1.0
        hum = bytrack(DrumMachine.song_hits(h; repeats = 1, countin = 0, click = false))
        @test length(hum) == length(exact) && all(a[2:3] == b[2:3] for (a, b) in zip(hum, exact))
        dt = [(a[1] - b[1]) / SR * 1000 for (a, b) in zip(hum, exact)]
        @test all(abs.(dt) .<= 10.05) && any(dt .< -1) && any(dt .> 1)
        @test all(10^(-3 / 20) - 1e-4 <= a[4] <= 10^(3 / 20) + 1e-4 for a in hum) && any(a[4] != 1 for a in hum)
        @test all(e[4] == 1 for e in exact)
    end

    @testset "Log" begin
        D = DrumMachine
        mktempdir() do dir
            f = joinpath(dir, "log", "drummachine.log")
            D.logev("not written")                                         # no program logger: nothing
            l = D.start_log!(path = f, max = 2000)
            try
                @test D.LOGGER[] === l && D.start_log!(path = f) === l      # only once
                D.logev("kit loaded"; name = "X", seconds = 0.5)
                @warn "something odd" value = 3
                try error("boom") catch e; @error "it failed" exception = (e, catch_backtrace()) end
                txt = read(f, String)
                @test occursin("INFO   start: program", txt) && occursin("version=", txt)
                @test occursin("INFO   kit loaded  name=X  seconds=0.5", txt)
                @test occursin(r"WARN   something odd  value=3  \(runtests.jl:\d+\)", txt)
                @test occursin("ERROR  it failed", txt) && occursin("boom", txt)
                for i in 1:60; D.logev("event $i"; pad = "x"^40); end           # beyond 2000 bytes
                @test isfile(f * ".1") && filesize(f) < 2000 && occursin("event 60", read(f, String))
            finally
                D.stop_log!()
            end
            @test D.LOGGER[] === nothing && !(D.global_logger() isa D.DMLogger)
            @test !isempty(D.info_text(:de)) && occursin("drummachine.log", D.info_text(:en))
        end
    end

    @testset "MIDI" begin
        D = DrumMachine
        id(m, n) = haskey(m, n) ? D.TRACK_IDS[m[n]] : nothing
        m = D.midi_note_map(Dict{String,Any}())                  # TD-27 table, GM as fallback
        @test [id(m, n) for n in (36, 38, 40, 37, 47, 58, 26, 22, 44, 52, 59, 53, 35, 41, 60, 48)] ==
              ["Kick", "Snare", "Snare", "Rim", "Tom2", "FloorTom", "HHOpen", "HiHat", "HHPedal", "Crash",
               "Ride", "RideBell", "Kick", "FloorTom", nothing, "Tom"]
        m = D.midi_note_map(Dict("midi_map" => Dict("38" => "Rim", "60" => "Crash", "36" => "off", "x" => "Kick")))
        @test id(m, 38) == "Rim" && id(m, 60) == "Crash" && id(m, 36) === nothing && id(m, 40) == "Snare"
        hh, sn, kk = D.track_index("HiHat"), D.track_index("Snare"), D.track_index("Kick")
        c = D.midi_config(Dict("midi_ghost" => 30, "midi_accent" => 100, "midi_offset_ms" => 12,
                               "midi_levels" => Dict("HiHat" => [36, 66], "Snare" => [50, 40], "x" => [1, 2])))
        @test [D.velocity_level(v, c, sn) for v in (1, 29, 30, 99, 100, 127)] == [1, 1, 2, 2, 3, 3]
        @test [D.velocity_level(v, c, hh) for v in (35, 36, 65, 66)] == [1, 2, 2, 3]   # own thresholds
        d = D.midi_config(Dict{String,Any}())
        @test (d.ghost, d.accent, d.offset_ms, c.offset_ms) == (45, 105, 0.0, 12.0)
        # calibration: hi-hat played loud/soft as on the TD-27 (edge 66-127, bow 33-60), snare with
        # ghosts, kick only normal, toms too few hits
        cal = vcat([(hh, v, 3) for v in 66:4:126], [(hh, v, 2) for v in 33:2:60], [(hh, 13, 2)],
                   [(sn, v, 2) for v in 46:3:82], [(sn, v, 1) for v in (23, 27, 31, 36)],
                   [(kk, v, 2) for v in 38:3:83], [(D.track_index("Tom"), 120, 2)])
        new = D.calibrate_levels(cal, d)
        @test sort!(collect(keys(new))) == sort!([hh, sn, kk])
        @test new[hh][1] <= 33 && 61 <= new[hh][2] <= 66                    # soft = normal, loud = accent
        @test 37 <= new[sn][1] <= 46 && new[sn][2] == 105 && new[kk] == (38, 105)
        mis(t) = count(h -> h[1] == t && D.velocity_level(h[2], new[t]...) != h[3], cal)
        @test mis(hh) <= 1 && mis(sn) == 0 && mis(kk) == 0
        @test D.level_boundary([10, 20, 30], [70, 80]) == 48                # gap: middle of the medians 20 and 75
        # whole take: hits 20 ms late -> offset +20; a stray hit far off does not count for the levels
        late = [(h..., 20.0 + isodd(i)) for (i, h) in enumerate(cal)]
        lv, off, med = D.calibrate(vcat(late, [(sn, 127, 1, 140.0)]), c)
        @test 20 <= med <= 21 && off == round(12 + med; digits = 1)         # 12 ms set before
        @test delete!(copy(lv), D.track_index("HHOpen")) == D.calibrate_levels(cal, c)
        @test D.calibrate(cal[1:10] .|> h -> (h..., 2.0), d)[2] === nothing   # too few hits, too small
        @test lv[D.track_index("HHOpen")] == lv[hh]                         # one cymbal: both hi-hat tracks
        ep = preset("Einmessen").patterns[1]                                 # open hi-hat counts where the hi-hat is
        @test D.cal_target(ep, D.track_index("HHOpen"), 1) == (hh, 3) && D.cal_target(ep, sn, 1) === nothing
        # a take: wait for the first hit, warm-up, measuring, ends after a pause or without any hit
        tk = D.CalTake(100.0, 24.0)
        @test D.cal_phase(tk, 150) == :wait && D.cal_end_reason(tk, 150) === nothing
        @test D.cal_end_reason(tk, 100 + D.CAL_WAIT_S + 1) == :timeout
        D.cal_add!(tk, 200, hh, 100, 3, 10.0)                                # first hit: warm-up
        @test D.cal_phase(tk, 210) == :warmup && D.cal_end_reason(tk, 222) === nothing
        for i in 0:39; D.cal_add!(tk, 225 + 0.2i, isodd(i) ? hh : sn, 60, 2, 15.0); end
        @test count(h -> h.measured, tk.hits) == 40 && !tk.hits[1].measured
        @test D.cal_end_reason(tk, 233 + D.CAL_IDLE_S - 1) === nothing && D.cal_end_reason(tk, 233 + D.CAL_IDLE_S + 1) == :pause
        res = D.cal_result(tk, d)
        @test length(res.hits) == 40 && res.offset == 15.0 && D.cal_hit_rate(res.hits, sn, (45, 105)) == 1
        @test D.bar_seconds(preset("Einmessen"), preset("Einmessen").patterns[1]) == 3.0   # 4/4 at 80 BPM
        # recording into a new song: bar and step from the engine position, equal bars share a pattern
        rt = D.RecTake(120, 4, 16, 1000.0, 50.0)                          # step = 5512.5 samples
        sl = rt.steplen
        @test D.rec_cell(rt, 1000 + 17sl + 100) == (1, 2, 1000 * 100 / SR) && D.rec_cell(rt, 1000 - 0.4sl)[1:2] == (0, 1)
        @test D.rec_add!(rt, 51, 1000 - 3sl, hh, 90, 3) === nothing && rt.t_first == 0   # before the first bar
        @test D.rec_phase(rt) == :wait && D.rec_end_reason(rt, 50 + D.CAL_WAIT_S + 1) == :timeout
        groove(bar) = [(bar * 16 + s, hh, isodd(s ÷ 2) ? 3 : 2) for s in 0:2:14]
        for b in 2:5, (g, t, l) in vcat(groove(b), b == 4 ? [(b * 16 + 12, sn, 2)] : Tuple{Int,Int,Int}[])
            D.rec_add!(rt, 60 + b, 1000 + g * sl + 30, t, 70, l)
        end
        D.rec_add!(rt, 66, 1000 + (5 * 16 + 4) * sl, hh, 120, 1)            # same cell again, softer: louder stays
        @test D.rec_phase(rt) == :rec && D.rec_bars(rt) == 4 && D.rec_end_reason(rt, 66 + D.REC_IDLE_S + 1) == :pause
        song, info = D.rec_song(rt; name = "R", kit = "BlackPearl")
        @test song.chain == [1, 1, 2, 1] && length(song.patterns) == 2 && song.patterns[1].steps == 16
        @test song.patterns[1].grid[hh, 1:2:16] == UInt8[2, 3, 2, 3, 2, 3, 2, 3] && song.patterns[2].grid[sn, 13] == 2
        @test (info.bars, info.patterns, info.merged) == (4, 2, 0) && song.bpm == 120 && song.kit == "BlackPearl"
        song1, info1 = D.rec_song(rt; name = "R", kit = "X", maxpat = 1)
        @test song1.chain == [1, 1, 1, 1] && info1.merged == 1               # too many patterns: nearest one
        @test D.rec_steps(D.RecSetup(100, 8, 7)) == 32 && D.rec_steps(D.RecSetup(100, 3, 4)) == 12
        mktempdir() do dir
            withenv("XDG_CONFIG_HOME" => dir) do
                D.save_setting!("midi_levels", Dict("Crash" => [20, 90]))
                c2 = D.save_midi_levels!(Dict(hh => (30, 64)))
                @test c2.levels[hh] == (30, 64) && c2.levels[D.track_index("Crash")] == (20, 90) && c2.levels[sn] == (45, 105)
            end
        end
        msg(st, n, v) = Int32(st) | Int32(n) << 8 | Int32(v) << 16
        @test D.note_on(msg(0x99, 38, 100)) == (38, 100)
        @test D.note_on(msg(0x99, 38, 0)) === D.note_on(msg(0x89, 38, 64)) === D.note_on(msg(0xB0, 4, 50)) === nothing
        ch = Channel{Tuple{Int,Int}}(64); for _ in 1:65; D.try_put!(ch, (1, 2)); end
        @test length(ch.data) == 64                              # full channel: dropped, does not block
        # time -> engine position from the logged blocks, minus latency and offset
        clk = D.HitClock(); dt = round(Int, D.BLOCK / SR * 1e9); t0 = UInt64(10)^12
        for k in 0:69
            D.log_block!(clk, t0 + UInt64(k * dt), k * D.BLOCK)
        end
        ts, pos, _, _ = D.clock_snapshot(clk)
        @test length(ts) == 64 && issorted(ts) && pos[1] == 6 * D.BLOCK
        tm = ts[10] + UInt64(dt ÷ 2)
        @test D.heard_sample(ts, pos, tm, 0) ≈ pos[10] + D.BLOCK / 2 atol = 0.01
        @test D.heard_sample(ts, pos, ts[end] + UInt64(dt), 0) ≈ pos[end] + D.BLOCK rtol = 1e-6
        @test D.hit_delay(0.08, 10) ≈ 0.08 + D.BLOCK / SR + 0.01
        @test D.heard_sample(ts, pos, tm, D.hit_delay(0.05, -5)) ≈ pos[10] + D.BLOCK / 2 - (0.045 * SR + D.BLOCK) atol = 0.01
        jit = [t + UInt64(isodd(k) ? 4 * 10^6 : 0) for (k, t) in enumerate(ts)]     # bursty block times
        @test abs(D.heard_sample(jit, pos, tm, 0) - (pos[10] + D.BLOCK / 2)) < 0.005SR
        # grid cell: real step times (swing on 16ths), wrap to the next bar, count-in
        s = Song(bpm = 120, swing = 0.66, swing_on = 16, patterns = [Pattern(16), Pattern(8)], chain = [1, 2])
        s.patterns[2].bpm = 60
        b = 60 / 120 / 4 * SR                                    # straight 16th
        L1 = 2SR                                                 # bar of pattern 1: 2 s
        loop = ([0, -1], 2, 1)                                   # pattern mode with count-in, edit pattern 1
        bars = [D.BarMark(1000.0, 1, 0), D.BarMark(1000.0 + L1, 2, 1)]
        cell(x) = x === nothing ? nothing : x[1:2]
        at(x) = cell(D.record_step(s, loop..., bars, x))
        r = 1000 + L1                                            # start of the first real bar
        @test at(r + 2b + 100) == (1, 3) && D.record_step(s, loop..., bars, r + 2b + 100)[3] ≈ 100
        @test at(r + 0.62b) == (1, 1)                            # swung "e" lies at 1.32 b
        @test at(r + 1.1b) == (1, 2)
        @test at(r + L1 - 0.2b) == (1, 1)                        # last step rounds up: step 1 again
        @test at(1000 + L1 - 0.3b) == (1, 1)                     # count-in: early hit on the one
        @test at(1000 + L1 / 2) === nothing                      # count-in: ignored
        @test at(500.0) === nothing                              # before playback
        @test cell(D.record_step(s, loop..., bars[1:1], r + 5b)) == (1, 6)        # log one bar behind
        song = ([1, 2], 1, 1)                                    # song mode, chain 1 2
        @test cell(D.record_step(s, song..., [D.BarMark(0.0, 1, 1)], L1 - 0.1b)) == (2, 1)
        @test cell(D.record_step(s, song..., [D.BarMark(0.0, 2, 2)], 3 * 2b + 10)) == (2, 4)   # own tempo 60
        @test cell(D.record_step(s, song..., [D.BarMark(0.0, 2, 2)], L1 - 0.1b)) == (1, 1)     # chain loops
        @test D.record_step(s, [1], 0, 1, [D.BarMark(0.0, 1, 1)], L1 - 0.1b) === nothing   # end of song
        # swing on auto: a recorded "e" switches the grid to 16th swing, the engine already timed
        # the next steps with 8th swing; the logged step starts count
        a8 = Song(bpm = 120, swing = 0.7, swing_on = 0, patterns = [Pattern(16)])
        a8.patterns[1].grid[4, 1:2:16] .= 2
        st = [D.StepMark(sum(D.step_samples(a8, j, a8.patterns[1]) for j in 0:i-1; init = 0.0), i) for i in 0:7]
        a8.patterns[1].grid[2, 6] = 1
        @test cell(D.record_step(a8, [-1], 1, 1, [D.BarMark(0.0, 1, 1)], 4b + 2.8b, st)) == (1, 7)
        # the engine logs its bars; record_play! = edit pattern in a loop after one count-in bar
        eng = D.Engine(Song(bpm = 240, patterns = [Pattern(16)]), syn)
        D.record_play!(eng)
        @test eng.seq == [0, -1] && eng.loop_from == 2
        buf = zeros(Float32, D.BLOCK, 2)
        for _ in 1:200
            eng.clock.nb < 2 && D.render!(eng, buf)
        end
        _, _, bm, _, sm = D.clock_snapshot(eng.clock)
        @test [(x.seqpos, x.pat) for x in bm] == [(1, 0), (2, 1)] && bm[2].start - bm[1].start ≈ SR
        @test sm[1] == D.StepMark(bm[1].start, 0) && sm[17] == D.StepMark(bm[2].start, 0)
        # MIDI output of the sequencer (messages kept instead of sent): notes on channel 10 with
        # CC 4 before the hi-hat, note-off after 30 ms or before the same note, kit silent, pads still sound
        so = Song(bpm = 120, patterns = [Pattern(16)])
        g = so.patterns[1].grid; g[D.track_index("Kick"), 1] = 3; g[D.track_index("HHOpen"), 1:2] .= 2
        so.tracks[D.track_index("Kick")].vol = 0.5f0
        eng = D.Engine(so, syn); eng.seqout.sent = Tuple{Float64,Int32}[]
        D.start_seq!(eng, [-1], 1)
        quiet = true
        for _ in 1:60
            D.render!(eng, buf); quiet &= all(iszero, buf)
        end
        ev = [(round(t, digits = 1), m & 0xff, (m >> 8) & 0xff, m >> 16) for (t, m) in eng.seqout.sent]
        t1 = D.LEAD_IN / SR * 1000; t2 = t1 + 125
        notes = filter(e -> e[2] != 0xf8, ev)
        @test quiet && notes[1:6] == [(t1, 0xfa, 0, 0), (t1, 0x99, 36, 60), (t1, 0xb9, 4, 0), (t1, 0x99, 46, 90),
                                      (t1 + 30, 0x89, 36, 0), (t1 + 30, 0x89, 46, 0)]
        @test (t2, 0x99, 46, 90) in ev && issorted(first.(ev))
        # MIDI clock: 24 ticks per beat from the Start on; level scales the velocity; Stop after playback
        @test count(e -> e[2] == 0xf8 && e[1] < t1 + 500 - 1, ev) == 24 && (t1 + 500, 0xf8, 0, 0) in ev
        eng.seqout.gain = 0.5; empty!(eng.seqout.sent); D.start_seq!(eng, [-1], 1)
        for _ in 1:12; D.render!(eng, buf); end
        D.stop!(eng); D.render!(eng, buf)
        m = [(x & 0xff, (x >> 8) & 0xff, x >> 16) for (_, x) in eng.seqout.sent]
        @test m[1] == (0xfc, 0, 0) && (0x99, 36, 30) in m && count(==((0xfc, 0, 0)), m) == 2
        put!(eng.pads, (D.track_index("Snare"), 2)); D.render!(eng, buf)
        @test !all(iszero, buf)
        # devices: never throws (CI has no ALSA sequencer); loopback through "Midi Through" if present
        ins = D.midi_inputs()
        @test ins isa Vector{String}
        if "Midi Through Port-0" in ins
            # setup player with a MIDI entry, its output on the same port as the input: the audio
            # thread's path (mix_player!) sends without allocating, the reader gets the note
            pads = Channel{Tuple{Int,Int}}(8)                    # monitor on: hits also go to the pads
            mi = D.open_midi("Midi Through Port-0"; pads, monitor = Threads.Atomic{Bool}(true))
            pl = D.Player(); B = D.BLOCK
            pl.items = [zeros(Float32, 4B, 2)]; pl.cues = [0]; pl.delays = [0.0]; pl.beeps = [false]
            pl.mframe = [[1, 1, 2B + 5]]; pl.mmsg = [[msg(0x99, 38, 0), msg(0xB9, 4, 50), msg(0x99, 38, 97)]]
            pl.mchans = [D.midi_channels(pl.mmsg[1])]
            p = D.open_midi_out("Midi Through Port-0")
            @test p != C_NULL && D.PM_OPEN[] == 2
            pl.mout[] = UInt(p); pl.auto = false
            D.player_start!(pl, 1; pause = false)
            buf = zeros(Float32, B, 2)
            sent = time_ns()
            D.mix_player!(pl, buf); D.mix_player!(pl, buf)
            # in a function: @allocated at top level would compile this whole testset (+20 s)
            block_alloc(pl, buf) = @allocated D.mix_player!(pl, buf)
            @test block_alloc(pl, buf) == 0 && pl.mi == 4                      # this block sent the note
            D.player_stop!(pl); D.mix_player!(pl, buf)
            @test pl.moff == 0 && !D.player_active(pl)                         # All Notes Off sent
            hits = D.MidiHit[]
            for _ in 1:200
                append!(hits, D.take_hits!(mi)); isempty(hits) || break; sleep(0.005)
            end
            so = D.SeqOut()                                      # main window on the same port: stream shared
            @test D.seq_out_open!(so, ReentrantLock(), "Midi Through Port-0") && so.mout[] == UInt(p) && D.PM_OPEN[] == 2
            D.seq_out_close!(so, ReentrantLock())
            @test so.mout[] == 0 && D.PM_OPEN[] == 2
            D.midi_out_close!(pl, ReentrantLock())
            D.close_midi!(mi)
            @test [(h.note, h.vel) for h in hits] == [(38, 97)] && take!(pads) == (2, 2) && !isready(pads)
            @test !isempty(hits) && 0 <= Int(hits[1].t) - Int(sent) < 1e9
            @test D.PM_OPEN[] == 0 && mi.task === nothing && pl.mout[] == 0
        else
            @test_skip "no MIDI loopback port"
        end
    end

    @testset "MIDI-Export" begin
        D = DrumMachine
        function smf(path)                                    # minimal reader: notes, tempos, signatures, end tick
            b = read(path); i = 23; t = 0
            notes = Tuple{Int,Int,Int}[]; tempos = Tuple{Int,Float64}[]; sigs = Tuple{Int,Int,Int}[]; offs = 0
            ccs = Tuple{Int,Int,Int}[]; order = UInt8[]
            @test b[1:4] == b"MThd" && b[9:14] == [0, 0, 0, 1, 0x03, 0xc0] && b[15:18] == b"MTrk"
            while i <= length(b)
                d = 0; while true; c = b[i]; i += 1; d = d << 7 | (c & 0x7f); c < 0x80 && break; end
                t += d; st = b[i]; i += 1
                if st == 0xff
                    len = b[i+1]; dat = b[i+2:i+1+len]
                    b[i] == 0x51 && push!(tempos, (t, 60e6 / (Int(dat[1]) << 16 | Int(dat[2]) << 8 | dat[3])))
                    b[i] == 0x58 && push!(sigs, (t, dat[1], 2^Int(dat[2])))
                    i += 2 + len
                else
                    st == 0x99 ? push!(notes, (t, b[i], b[i+1])) : st == 0xb9 ? push!(ccs, (t, b[i], b[i+1])) : (offs += 1)
                    st == 0x99 && push!(order, b[i]); st == 0xb9 && push!(order, 0x80 | b[i+1]); i += 2
                end
            end
            return notes, tempos, offs, t, sigs, ccs, order
        end
        s = Song(name = "M", bpm = 100, patterns = [pattern_from_rows(Dict("Kick" => "X...x...", "HiHat" => "o.x.x.x.",
                                                                            "Snare" => "....x..."); steps = 8)])
        s.patterns[1].orn[2, 5] = D.ORN_FLAM
        mktempdir() do dir
            f = export_midi(joinpath(dir, "m.mid"), s; repeats = 1, countin = 1, click = false)
            n, tp, offs, tend, sg, cc, ord = smf(f)
            B = 1920                                                                   # 8 steps = 2 beats, count-in as long
            @test tp == [(0, 100.0)] && offs == length(n) && tend == 2B && sg == [(0, 2, 4)]   # 2/4 once
            # hi-hat opening (CC 4) right before each hi-hat note: closed 127, open 0
            @test cc == [(x[1], 4, 127) for x in n if x[2] == 42]
            @test all(ord[k-1] == 0x80 | 127 for k in eachindex(ord) if ord[k] == 42)
            @test [x for x in n if x[1] < B] == [(0, 34, 120), (960, 33, 90)]
            @test (B, 36, 120) in n && (B, 42, 35) in n && (B + 960, 36, 90) in n && (B + 480, 42, 90) in n
            g = [x for x in n if x[2] == 38]                                           # flam: grace before the snare
            @test length(g) == 2 && g[2][1] == B + 960 && 0 < g[2][1] - g[1][1] < 100 && g[1][3] < g[2][3]
            m = D.midi_note_map(Dict{String,Any}()); c = D.midi_config(Dict{String,Any}())
            @test [m[k] for k in D.MIDI_OUT_NOTES] == 1:NTRACKS                       # recording reads them back
            @test [D.velocity_level(v, c, 1) for v in D.MIDI_OUT_VEL] == [1, 2, 3]
            s.swing = 2 / 3; s.patterns[1].bpm = 120; s.tracks[2].mute = true          # swing, tempo, mute
            n, tp, _, _ = smf(export_midi(f, s; repeats = 1, countin = 0))
            @test tp == [(0, 120.0)] && [x[1] for x in n if x[2] == 42][1:2] == [0, 640] && !any(x -> x[2] == 38, n)
            # reader for the setup player: round trip with a tempo change (pattern 2 at 60 BPM)
            s.tracks[2].mute = false; s.swing = 0.5; s.patterns[1].bpm = 0
            push!(s.patterns, pattern_from_rows(Dict("Kick" => "x.x.x.x.", "HHOpen" => "x......."); steps = 8))
            s.patterns[2].bpm = 60; s.chain = [1, 2]
            m = D.read_midi_file(export_midi(f, s; repeats = 1, countin = 0, click = false))
            hits, _, total = D.song_hits(s; repeats = 1, countin = 0, click = false)
            on = [t for (t, x) in zip(m.times, m.msgs) if x & 0xff == 0x99 && x >> 16 > 0]
            @test length(on) == length(unique((h[1], h[2]) for h in hits)) && issorted(m.times)
            @test isapprox(m.length, total / SR; atol = 0.002) && on[end] ≈ 1.2 + 1.5   # bar 2 after 2 beats at 100, last kick 1.5 beats at 60
            @test any(((t, x),) -> t ≈ 1.2 && x == 0xb9 | 4 << 8, zip(m.times, m.msgs))    # CC 4 = 0 before the open hi-hat
        end
        # format 1, running status, sysex and tempo in track 1, events of both tracks merged
        trk(b::Vector{UInt8}) = [b"MTrk"; reinterpret(UInt8, [hton(UInt32(length(b)))]); b]
        f1 = [b"MThd"; UInt8[0, 0, 0, 6, 0, 1, 0, 2, 0, 96];
              trk(UInt8[0, 0xff, 0x51, 3, 0x0f, 0x42, 0x40, 96, 0xff, 0x51, 3, 0x07, 0xa1, 0x20, 96, 0xff, 0x2f, 0]);
              trk(UInt8[0, 0x99, 38, 100, 48, 38, 0, 0, 0xf0, 2, 1, 0xf7, 48, 0xc9, 5, 96, 0xb9, 4, 7, 0, 0xff, 0x2f, 0])]
        m1 = D.parse_midi(f1)
        @test m1.times ≈ [0, 0.5, 1, 1.5] && m1.length ≈ 1.5                           # 60 BPM, then 120
        @test m1.msgs == Int32[0x99 | 38 << 8 | 100 << 16, 0x99 | 38 << 8, 0xc9 | 5 << 8, 0xb9 | 4 << 8 | 7 << 16]
        @test D.midi_channels(m1.msgs) == 0x0200
        @test_throws ErrorException D.parse_midi(f1[1:end-5])                           # cut off
        @test_throws ErrorException D.parse_midi([f1[1:14]; trk(UInt8[0, 0x26, 1])])      # data byte without status
        @test_throws ErrorException D.parse_midi(f1[1:40])                              # 2 tracks announced, 1 there
        @test D.parse_midi([f1[1:12]; UInt8[0xe7, 40]; f1[15:end]]).times ≈ [0, 0.048, 0.096, 0.192]   # SMPTE 25 × 40: 1 ms
        @test_throws ErrorException D.parse_midi([f1[1:12]; UInt8[0xe7, 0]; f1[15:end]])       # SMPTE, 0 ticks per frame
        # time signatures: odd meters, triplet bars without one, pickup bar for a flam on step 1
        sig(s) = [(e[1], e[3][4], 2^e[3][5]) for e in first(D.midi_events(s; repeats = 1, countin = 0, click = false))
                  if e[3][1:2] == [0xff, 0x58]]
        @test sig(preset("Taktart: 7/8 (2+2+3)")) == [(0, 14, 16)]
        @test D.bar_signature(7, 2) == (7, 8) && D.bar_signature(9, 6) == (3, 8) && D.bar_signature(10, 3) === nothing
        @test !D.midi_bars_ok(Song(steps_per_beat = 3, patterns = [Pattern(12), Pattern(10)], chain = [1, 2, 1]))
        e = Song(); e.chain = [1]; e.patterns[1].grid[2, 1] = 2; e.patterns[1].orn[2, 1] = D.ORN_FLAM
        @test sig(e) == [(0, 1, 16), (240, 4, 4)]
    end

    @testset "Export" begin
        s = preset("Rock: 8tel")
        y = render_song(s, bp; repeats = 1, countin = 1)
        @test size(y, 1) >= round(Int, song_seconds(s; repeats = 1, countin = 1) * SR) - 1
        @test maximum(abs, y) <= 1
        # first beat comes after the count-in
        bar = round(Int, song_seconds(s; repeats = 1, countin = 0) / length(s.chain) * SR)
        @test maximum(abs, y[1:bar÷8, :]) > 0.01          # count-in click audible
        # mute applies to the export
        s2 = preset("Rock: 8tel"); foreach(t -> t.mute = true, s2.tracks)
        @test maximum(abs, render_song(s2, bp; repeats = 1, countin = 0)) < 1e-3
        mktempdir() do d
            # file names ASCII only (Roland TD-27 etc.)
            @test ascii_filename("Übung: Größe ä ö ü ß – Café.wav") == "Uebung_ Groesse ae oe ue ss _ Cafe.wav"
            f = export_wav(joinpath(d, "Grüße Ölfaß.wav"), s, bp; repeats = 1)
            @test basename(f) == "Gruesse Oelfass.wav" && isfile(f)
            # standard WAV: RIFF/WAVE, fmt (16 bytes, PCM), data - nothing else
            b = read(f)
            @test b[1:4] == b"RIFF" && b[9:12] == b"WAVE" && b[13:16] == b"fmt "
            @test reinterpret(UInt32, b[17:20])[1] == 16
            @test reinterpret(UInt16, b[21:24]) == [1, 2]                  # PCM, stereo
            @test reinterpret(UInt32, b[25:28])[1] == 44100
            @test reinterpret(UInt16, b[35:36])[1] == 16                   # bits
            @test b[37:40] == b"data" && 44 + reinterpret(UInt32, b[41:44])[1] == length(b)
            f = export_wav(joinpath(d, "a.wav"), s, bp; repeats = 1, mono = true)
            @test size(DrumMachine.WAV.wavread(f)[1], 2) == 1
            # mono already applies when rendering (= live playback): both channels identical
            sm = copy(s); sm.mono = true
            ym = render_song(sm, bp; repeats = 1)
            @test ym[:, 1] == ym[:, 2]
            @test y[:, 1] != y[:, 2]
        end
    end

    @testset "Sample-Onsets" begin
        # no sample may start later than 2 ms after onset (otherwise timing wobbles)
        for layers in bp.layers, layer in layers, s in layer
            x = s.l
            pk = maximum(abs, x)
            @test findfirst(v -> abs(v) > 0.1pk, x) / SR < 0.002
        end
    end

    @testset "$name (falls installiert)" for name in ("CrocellKit", "VirtuosityDrums")
        all_es = kit_entries()                    # all folders: kitbuild installs into the user kit dir
        k = findfirst(e -> e.name == name, all_es)
        if k === nothing
            @info "$name nicht installiert (tools/build_*.jl) – Test übersprungen"
        else
            cr = get_kit(all_es[k])
            @test all(length(l) == 5 for l in cr.layers)
            @test all(DrumMachine.isstereo(s) for ls in cr.layers for l in ls for s in l)
            @test cr.level_gain == (0.9f0, 1.0f0, 1.0f0)
            y = render_song(preset("Rock: 8tel"), cr; repeats = 1)
            @test 0.3 < maximum(abs, y) < 0.98
        end
    end

    @testset "Velocity-Layer & Round-Robin" begin
        L = DrumMachine.level_layers
        @test (L(1, 5), L(2, 5), L(3, 5)) == (1:2, 3:4, 5:5)
        @test (L(1, 1), L(2, 1), L(3, 1)) == (1:1, 1:1, 1:1)
        @test (L(1, 10), L(2, 10), L(3, 10)) == (1:4, 5:8, 9:10)
        for nl in 1:20, lv in 1:3
            @test !isempty(L(lv, nl)) && first(L(lv, nl)) >= 1 && last(L(lv, nl)) <= nl
        end
        # never the same recording twice in a row, as long as there is more than one
        mk() = DrumMachine.Sample(rand(Float32, 10))
        pool = [(mk(), 1f0) for _ in 1:3]
        rng = DrumMachine.MersenneTwister(1)
        prev = DrumMachine.Sample(Float32[])
        for _ in 1:200
            s, _ = DrumMachine.pick_sample(rng, pool, prev)
            @test s !== prev
            prev = s
        end
        # even levels (regression: a normal hit from a wide layer was as loud as an accent):
        # one loudness per level, accent >= normal + 6 dB, ghost <= normal - 8 dB
        lvl(pool) = [DrumMachine.attack_db(s) + 20log10(g) for (s, g) in pool]
        function even(k::DrumMachine.Kit)
            for p in k.pools
                db = lvl.(p)
                all(d -> maximum(d) - minimum(d) < 0.01, db) || return false
                (db[3][1] >= db[2][1] + 5.99 && db[1][1] <= db[2][1] - 7.99) || return false
            end
            return true
        end
        @test even(bp) && even(DrumMachine.synth_kit())        # flat kits: accent is raised
        amp(db...) = [DrumMachine.Sample(fill(Float32(10^(d / 20)), 2000)) for d in db]
        wide = [amp(-30, -26), amp(-22, -20), amp(-17, -15, -13), amp(-11, -9, -6), amp(-4, -2, 0)]
        k = DrumMachine.Kit("wide", [wide for _ in 1:NTRACKS], zeros(Float32, NTRACKS), ones(Float32, NTRACKS),
                            zeros(Int, NTRACKS), (1f0, 1f0, 1f0))
        @test even(k)
        @test length(k.pools[1][2]) == 4          # normal (-17 … -6, median -12): only -15 … -9 used
    end

    @testset "Metronom" begin
        D = DrumMachine
        function onsets(eng, secs)                  # first sample of each click (silence before)
            out = zeros(Float32, D.BLOCK, 2); on = Int[]; quiet = 1000; i = 0
            for _ in 1:ceil(Int, secs * SR / D.BLOCK)
                D.render!(eng, out)
                for a in abs.(view(out, :, 1))
                    a > 1f-3 && quiet >= 400 && push!(on, i)
                    quiet = a > 1f-3 ? 0 : quiet + 1; i += 1
                end
            end
            return on
        end
        eng = D.Engine(preset("Leer"), syn); m = eng.metro
        m.bpm = 120; D.metro_start!(m)
        @test onsets(eng, 2.1) ⊆ (0:4) .* 22050 .+ (0:1)'           # quarters, sample-accurate
        m.subdiv = 2; D.metro_stop!(m); D.metro_start!(m)
        @test length(onsets(eng, 1.05)) == 5                         # 8ths
        m.subdiv = 1; m.accent = 4; D.metro_stop!(m); D.metro_start!(m)
        @test first(onsets(eng, 1.1)) in 11025:11026                 # offbeats only
        m.accent = 3; @test [l for (_, l) in D.metro_events(m)] == [1, 1] && D.metro_events(m)[1][1] == 1.0
        m.accent = 1; m.meter = findfirst(o -> o[1] == "7/8 (2+2+3)", D.METER_OPTS)
        @test D.metro_events(m) == [(0.0, 3), (0.5, 1), (1.0, 2), (1.5, 1), (2.0, 2), (2.5, 1), (3.0, 1)]
        m.meter = 4; m.gap_play = 1; m.gap_mute = 1; D.metro_stop!(m); D.metro_start!(m)
        on = onsets(eng, 4.05)
        @test length(on) == 5 && on[end] in 176400:176401           # bar 2 silent, bar 3 plays
        m.gap_mute = 0; m.trainer_step = 10; m.trainer_bars = 1; m.trainer_max = 135
        D.metro_stop!(m); D.metro_start!(m); onsets(eng, 6)
        @test m.bpm == 135
        for k in eachindex(D.SOUND_OPTS)
            a, b, c = D.metro_sounds(k, syn)
            @test 0.3 < maximum(abs, a.l) <= 1 && !isempty(b.l) && !isempty(c.l)
        end
        d = D.metro_settings(m); m2 = D.Metronome(); D.metro_apply_settings!(m2, d)
        @test D.metro_settings(m2) == d
        @test D.metro_apply_settings!(D.Metronome(), Dict("bpm" => "x", "meter" => "13/7")).bpm == 100
    end

    @testset "Drum-JSON-Import" begin
        D = DrumMachine
        s, notes = import_drum_json(joinpath(@__DIR__, "drum_json_example.json"))
        @test s.name == "drum_json_example" && s.bpm == 96 && s.steps_per_beat == 4 && s.swing == 0.5
        @test s.chain == [1, 2] && all(p -> p.steps == 16, s.patterns) && s.kit == "CrocellKit" && s.fx == "Room"
        @test D.row_string(s.patterns[1], D.track_index("Kick"))[1:16] == "x.......x.x....."
        @test D.row_string(s.patterns[2], D.track_index("HiHat"))[1:16] == "x.x.x.x.x.x.x..."
        @test D.row_string(s.patterns[2], D.track_index("Crash"))[1:16] == "x..............." && isempty(notes)
        tr(snd; vol = Dict(), var = Dict(), kw...) = Dict{String,Any}("sound" => snd, "slot_volume" => vol,
                                                                      "slot_variant" => var, (String(k) => v for (k, v) in kw)...)
        function jw(io, x)                     # tiny JSON writer: JSON.json costs ~1 s to compile
            if x isa AbstractDict
                print(io, '{'); for (i, (k, v)) in enumerate(x); i > 1 && print(io, ','); print(io, '"', k, "\":"); jw(io, v); end; print(io, '}')
            elseif x isa AbstractVector
                print(io, '['); for (i, v) in enumerate(x); i > 1 && print(io, ','); jw(io, v); end; print(io, ']')
            else
                print(io, x isa AbstractString ? "\"$x\"" : x === nothing ? "null" : x)
            end
        end
        js(tracks; kw...) = sprint(jw, Dict{String,Any}("name" => "Test",
            "tempo" => 120, "beat_div" => 4, "beats_per_bar" => 4, "bars" => 1, "tracks" => tracks, (String(k) => v for (k, v) in kw)...))
        s, notes = import_drum_json(js([
            tr("x_hihat"; vol = Dict("0" => 1, "2" => 0.6, "4" => 0.3), var = Dict("4" => 1)),
            tr("x_snare"; vol = Dict("4" => 1), var = Dict("4" => 1)),
            tr("x_ride"; vol = Dict("8" => 1), var = Dict("8" => 1)),
            tr("x_tom_hi"; vol = Dict("12" => 1)), tr("x_tom_med"; vol = Dict("13" => 1)),
            tr("x_tom_lo"; vol = Dict("14" => 1)), tr("x_kick"; vol = Dict("0" => 1), repeat = 4),
            tr("x_conga"; vol = Dict("1" => 1))]; shuffle = 0.67))
        g = s.patterns[1].grid; ti = D.track_index
        @test g[ti("HiHat"), [1, 3]] == [0x03, 0x02] && g[ti("HHOpen"), 5] == 0x01      # dynamics, open
        @test g[ti("Rim"), 5] == 0x02 && g[ti("RideBell"), 9] == 0x02                    # variants
        @test g[ti("Tom"), [13, 14]] == [0x02, 0x02] && g[ti("FloorTom"), 15] == 0x02
        @test findall(!iszero, g[ti("Kick"), 1:16]) == [1, 5, 9, 13]                      # repeat
        @test s.name == "Test" && s.swing ≈ 0.67 && s.swing_on == 16
        @test any(contains("conga"), notes) && any(contains("Tom"), notes)
        @test D.djson_track("x_hihat_closed", 0) == "HiHat" && D.djson_track("x_hihat_pedal", 0) == "HHPedal"
        # shuffle as integer code, null name and kit, repeat keeps variant and flam
        s, _ = import_drum_json(js([tr("x_kick"; vol = Dict("0" => 1)),
                                    tr("x_hihat"; vol = Dict("2" => 1), var = Dict("2" => 1), repeat = 4, slot_flam = Dict("2" => 1))];
                                   shuffle = 1, name = nothing, kit = nothing))
        g = s.patterns[1].grid
        @test s.swing ≈ 0.67 && s.name == "JSON-Import" && s.kit == "CrocellKit"
        @test all(g[ti("HHOpen"), [3, 7, 11, 15]] .> 0) && all(iszero, g[ti("HiHat"), :])
        @test all(s.patterns[1].orn[ti("HHOpen"), [3, 7, 11, 15]] .== D.ORN_FLAM)
        s, _ = import_drum_json(js([tr("x_kick"; vol = Dict("0" => 1, "3" => 1))]; beat_div = 1, beats_per_bar = 4))
        @test s.steps_per_beat == 2 && D.row_string(s.patterns[1], 1)[1:8] == "x.....x."
        # 32nd grid: kept as 32nds at the original tempo; only 16ths used -> 16th grid
        s, notes = import_drum_json(js([tr("x_kick"; vol = Dict("0" => 1, "31" => 1))]; beat_div = 8))
        @test s.bpm == 120 && s.steps_per_beat == 8 && s.patterns[1].steps == 32 && isempty(notes)
        @test findall(!iszero, s.patterns[1].grid[1, 1:32]) == [1, 32]
        s, _ = import_drum_json(js([tr("x_kick"; vol = Dict("0" => 1, "30" => 1))]; beat_div = 8))
        @test s.bpm == 120 && s.steps_per_beat == 4 && s.patterns[1].steps == 16
        @test findall(!iszero, s.patterns[1].grid[1, 1:16]) == [1, 16]
        @test_throws Exception import_drum_json(js([tr("x_kick"; vol = Dict("1" => 1))]; beat_div = 8, beats_per_bar = 5))
        # newer files: per-slot values as arrays (index = slot, null/0 = nothing)
        av = Any[0 for _ in 1:16]; av[1] = 1; av[5] = 0.4; av[9] = 1
        dv = Any[1 for _ in 1:16]; dv[[1, 5, 9]] .= nothing
        s, notes = import_drum_json(js([tr("x_snare"; vol = av, var = Any[0 for _ in 1:16], slot_delay = dv,
                                           slot_flam = Any[0 for _ in 1:16])]))
        @test D.row_string(s.patterns[1], D.track_index("Snare"))[1:16] == "X...o...X......." && isempty(notes)
        @test D.is_drum_json(js([tr("x_kick"; vol = Dict("0" => 1))])) && !D.is_drum_json("{}")
        @test_throws Exception import_drum_json("{\"a\": 1}")
        mktempdir() do dir
            src = joinpath(@__DIR__, "drum_json_example.json")
            res = D.import_drum_json_files([src, src]; dir)
            @test basename.(first.(res)) == ["drum_json_example.toml", "drum_json_example 2.toml"]
            @test load_song(res[2][1]).chain == [1, 2]
        end
    end

    @testset "Beispiel-Songs" begin
        for f in filter(endswith(".toml"), readdir(DrumMachine.SONG_DIR; join = true))
            s = load_song(f)
            @test !isempty(s.chain) && all(1 <= i <= length(s.patterns) <= DrumMachine.MAXPATTERNS for i in s.chain)
        end
        s = load_song(joinpath(DrumMachine.SONG_DIR, "Double-Time Swing (Whiplash-Stil).toml"))
        @test s.bpm == 330 && length(s.chain) == 60 && 28 in [p.steps for p in s.patterns]
        @test DrumMachine.orn_string(s.patterns[7], DrumMachine.track_index("Snare")) == "2"^16 * "z"^16   # roll intro
        @test sum(s.patterns[c].steps for c in s.chain) == 73 * 16 + 8 * 28   # 81 bars, 8 of them in 7/4
        @test length(s.patterns) == 17 && s.tracks[DrumMachine.track_index("Crash")].swap
    end

    @testset "Speichern/Laden" begin
        s = preset("Funk: Ghost Notes"); s.tracks[2].mute = true; s.bpm = 97; s.swing_on = 8; s.mono = true; s.human = 0.35
        mktempdir() do d
            f = save_song(joinpath(d, "x.toml"), s)
            s2 = load_song(f)
            @test s2.patterns[1].grid == s.patterns[1].grid
            @test s2.tracks[2].mute && s2.bpm == 97 && s2.swing_on == 8 && s2.mono && s2.human == 0.35
            # old file (no swing_version) with triplets and 0.5 -> exact triplets
            d = DrumMachine.song_to_dict(preset("Blues: Jump / Swing"))
            d["swing"] = 0.5; delete!(d, "swing_version")
            @test DrumMachine.song_from_dict(d).swing == 2 / 3
            d["swing_version"] = 2
            @test DrumMachine.song_from_dict(d).swing == 0.5
            x = DrumMachine.song_from_dict(Dict{String,Any}("bpm" => 0, "countin" => -1, "steps_per_beat" => 0, "repeats" => 0))
            @test (x.bpm, x.countin, x.steps_per_beat, x.repeats) == (100.0, 0, 4, 1)        # nonsense clamped
            x = DrumMachine.song_from_dict(Dict{String,Any}("bpm" => 1000, "countin" => 9))
            @test (x.bpm, x.countin) == (400.0, 4)
            save_song(f, s2); @test !isfile(f * ".tmp")                                         # written via temp file
        end
    end

    @testset "Letzte Sitzung" begin
        D = DrumMachine
        cfg = mktempdir()
        withenv("XDG_CONFIG_HOME" => cfg) do
            @test D.load_session() === nothing                    # first start: nothing stored
            s = D.preset("Rock: 8tel")
            push!(s.patterns, copy(s.patterns[1]))
            s.bpm = 123; s.kit = "808 (Synth)"; s.chain = [1, 2, 2]
            eng = D.Engine(s, syn)
            eng.edit_pat = 2; eng.songmode = true
            ses = D.new_session()
            f = joinpath(cfg, "mein.toml"); D.save_song(f, s)
            ses.edit_path[] = f; ses.edit_name[] = s.name
            @test D.save_session(eng, ses)
            @test !D.save_session(eng, ses)                       # unchanged: not written again
            r = D.load_session()
            @test r.song.bpm == 123 && r.song.kit == "808 (Synth)" && r.song.chain == [1, 2, 2]
            @test r.edit_pat == 2 && r.songmode && r.edit_path == f && r.edit_name == s.name
            @test !r.edit_on                                      # toggle was not switched on
            ses.edit_on[] = true; D.save_session(eng, ses)
            @test D.load_session().edit_on
            rm(f)                                                 # edited file gone: edit mode off
            r = D.load_session()
            @test r.edit_path == "" && r.edit_name == "" && !r.edit_on
            write(D.last_song_path(), "kaputt = [")              # unreadable file: fresh start
            @test D.load_session() === nothing
        end
    end
    @testset "Lo-Fi behält die Dynamik" begin
        D = DrumMachine
        x = Float32.(0.5 .* sin.(2π .* 200 .* (0:4409) ./ 44100))
        pk(a) = maximum(abs, D.lofi(hcat(a .* x, a .* x)))
        @test pk(1.8f0) ≈ 0.95f0 atol = 1e-4                     # loud: limited to 0.95
        @test pk(0.02f0) < 0.1                                    # quiet stays quiet
        @test pk(0.2f0) > pk(0.02f0)
    end
    @testset "GC-Pause" begin
        D = DrumMachine
        g = D.GCPause(0, false, 0.0, false, 0)
        up(a; free = 8 * 1024^3) = D.gcpause_update!(a; g, free)
        @test up(true) == :none && !g.off                        # off: nothing happens
        D.gcpause_set!(5; g)
        @test up(false) == :none && !g.off                       # not playing
        @test up(true) == :paused && g.off && g.until > time() + 290
        @test up(true) == :none && g.off
        @test up(false) == :stopped && !g.off
        @test up(true) == :paused
        g.until = time() - 1
        @test up(true) == :time && !g.off && g.spent
        @test up(true) == :none && !g.off                        # used up until the next stop
        @test up(false) == :none && !g.spent
        @test up(true; free = 0) == :none && !g.off              # too little memory: no pause
        @test up(true) == :paused
        @test up(true; free = 0) == :memory && !g.off
        up(false); up(true); D.gcpause_set!(0; g)                # choosing "off" releases right away
        @test !g.off && GC.enable(true)                          # collector is on again
    end
end
