using Test, DrumMachine, WAV
using DrumMachine: NTRACKS, SR, step_samples, MAXSTEPS

@testset "DrumMachine" begin
    kits = available_kits()
    @test any(k -> k.name == "BlackPearl", kits)
    @test [k.name for k in kits[end-1:end]] == ["808 (Synth)", "909 (Synth)"]
    for k in kits[end-1:end]
        y = render_song(preset("Pop: Disco"), k; repeats = 1)
        @test 0.2 < maximum(abs, y) < 0.98
    end
    bp = kits[1]
    @test all(length(l) == 5 for l in bp.layers)
    syn = kits[end-1]                     # 808 synth: one sample per level, deterministic, cheap

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
        @test parse_chain("1x3 2", 2) == [1, 1, 1, 2]
        @test parse_chain("1 5 2", 2) == [1, 2]
    end

    @testset "Fill" begin
        g = preset("Rock: 8tel").patterns[2]
        for st in eachindex(FILL_STYLES), spb in (4, 3)
            f = make_fill(g, spb, st)
            n = min(FILL_STYLES[st][2] * spb, g.steps)
            @test f.steps == g.steps
            @test f.grid[:, 1:g.steps-n] == g.grid[:, 1:g.steps-n]     # groove before it is kept
            @test any(!iszero, f.grid[:, g.steps-n+1:g.steps])
            @test f.grid[4, g.steps-n+1:g.steps] == zeros(UInt8, n)     # hi-hat rests during the fill
        end
        @test make_fill(g, 4, 1).grid == make_fill(g, 4, length(FILL_STYLES) + 1).grid
        @test row_string(make_fill(g, 4, 2), 7) == ".............x.."             # tom run-out: tom in the middle
        short = pattern_from_rows(Dict("Snare" => "X.X."))
        @test make_fill(short, 4, length(FILL_STYLES)).steps == 4                 # fill longer than pattern
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
            @test_throws Exception D.prepare_entry(D.SetEntry(joinpath(dir, "fehlt.toml")))
            # loop exports are refused, loop songs are rendered once (with count-in, not folded)
            @test D.is_loop_file("x/Rock 8tel Loop.wav") && D.is_loop_file("a_loop.WAV") && !D.is_loop_file("Looping.wav")
            save_wave(joinpath(dir, "m Loop.wav"), Wave(fill(0.25f0, 100), 22050))
            @test_throws Exception D.prepare_entry(D.SetEntry(joinpath(dir, "m Loop.wav")))
            s.loop = true; save_song(joinpath(dir, "l.toml"), s)
            @test size(D.prepare_entry(D.SetEntry(joinpath(dir, "l.toml"))), 1) > D.song_seconds(s; countin = 0) * SR
        end
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
    end

    @testset "Loop-Export" begin
        D = DrumMachine
        s = preset("Rock: 8tel"); s.chain = [2]; s.fx = "Hall"; s.fxmix = 0.5; s.master = 0.3
        L = render_song(s, syn; repeats = 1, loop = true)
        @test size(L, 1) == round(Int, D.song_seconds(s; repeats = 1, countin = 0) * SR)
        y = render_song(s, syn; repeats = 3, countin = 0)          # played through: middle bar = loop
        n = size(L, 1)
        @test maximum(abs, L .- y[n+1:2n, :]) < 1e-3
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
            withenv("XDG_CONFIG_HOME" => dir, "LANG" => "de_DE.UTF-8") do
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
                info = read(`ffprobe -v error -show_entries stream=codec_name,channels -of csv=p=0 $p`, String)
                @test strip(info) == "aac,2"
            end
        else
            @test_skip "ffmpeg not installed"
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
            @test any(occursin("11/11", m) for m in msgs) && occursin("CrocellKit", msgs[end])
            withenv("DRUMMACHINE_KIT_DIR" => joinpath(dir, "kits")) do      # found in the user kit dir
                @test joinpath(dir, "kits") in D.kit_dirs()
                # listing reads no samples; a kit is loaded once and then taken from the cache
                es = kit_entries([joinpath(dir, "kits")])
                @test [e.name for e in es] == ["CrocellKit", "808 (Synth)", "909 (Synth)"]
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
            withenv("DRUMMACHINE_NO_KIT_DOWNLOAD" => "1") do
                @test !D.auto_kits_enabled() && D.auto_fetch_kits!(println, println) === nothing
            end
        end
    end

    @testset "Song-Ordner" begin
        D = DrumMachine
        @test D.song_dir() == D.SONG_DIR                      # writable git checkout: songs/ as before
        mktempdir() do dir
            withenv("DRUMMACHINE_SONG_DIR" => joinpath(dir, "own")) do   # e.g. installed read-only
                @test D.song_dir() == joinpath(dir, "own") && isdir(D.song_dir())
                save_song(joinpath(D.song_dir(), "Mein Groove.toml"), preset("Rock: 8tel"))
                names = D.list_songs()
                @test "Mein Groove" in names && "Rock 8tel" in names   # own songs + examples
                @test D.song_file("Rock 8tel") == joinpath(D.SONG_DIR, "Rock 8tel.toml")
                @test D.song_file("Mein Groove") == joinpath(dir, "own", "Mein Groove.toml")
            end
            ro = joinpath(dir, "ro"); mkpath(ro); chmod(ro, 0o555)
            @test !D.dir_writable(ro) || Sys.iswindows() || get(ENV, "USER", "") == "root"
            chmod(ro, 0o755)
        end
    end

    @testset "Datei-Dialog" begin
        mktempdir() do bin
            fake = joinpath(bin, "zenity")
            withenv("PATH" => bin * ":" * ENV["PATH"]) do
                write(fake, "#!/bin/sh\necho /x/y.toml\n"); chmod(fake, 0o755)
                @test DrumMachine.pick_song_file() == "/x/y.toml"
                write(fake, "#!/bin/sh\nexit 1\n")
                @test DrumMachine.pick_song_file() == ""                  # cancel
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
        # triplet grid: default = exact triplets, swing shifts the third triplet
        t = Song(bpm = 120, steps_per_beat = 3)
        @test t.swing == 2 / 3
        @test step_samples(t, 0) ≈ step_samples(t, 1) ≈ step_samples(t, 2)
        t.swing = 0.75
        @test step_samples(t, 0) + step_samples(t, 1) ≈ 0.75 * 0.5SR
        @test sum(step_samples(t, k) for k in 0:11) ≈ 2SR
        # 32nd grid: 8 steps per beat, swing on 16ths moves the second 16th (steps 3–4) later
        z = Song(bpm = 120, steps_per_beat = 8, swing_on = 16)
        z.swing = 0.6
        @test step_samples(z, 0) == step_samples(z, 1) > step_samples(z, 2) == step_samples(z, 3)
        @test step_samples(z, 0) + step_samples(z, 1) ≈ 0.6 * 0.25SR
        @test sum(step_samples(z, k) for k in 0:31) ≈ 2SR
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
        k = findfirst(k -> k.name == name, kits)
        if k === nothing
            @info "$name nicht installiert (tools/build_*.jl) – Test übersprungen"
        else
            cr = kits[k]
            @test all(length(l) == 5 for l in cr.layers)
            @test all(DrumMachine.isstereo(s) for ls in cr.layers for l in ls for s in l)
            @test cr.level_gain == (0.9f0, 1.0f0, 1.0f0)
            y = render_song(preset("Rock: 8tel"), cr; repeats = 2)
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
        layers = [[mk(), mk()], [mk(), mk(), mk()], [mk()]]
        rng = DrumMachine.MersenneTwister(1)
        prev = DrumMachine.Sample(Float32[])
        for _ in 1:200
            s = DrumMachine.pick_sample(rng, layers, 2, prev)
            @test s !== prev
            prev = s
        end
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
        s = preset("Funk: Ghost Notes"); s.tracks[2].mute = true; s.bpm = 97; s.swing_on = 8; s.mono = true
        mktempdir() do d
            f = save_song(joinpath(d, "x.toml"), s)
            s2 = load_song(f)
            @test s2.patterns[1].grid == s.patterns[1].grid
            @test s2.tracks[2].mute && s2.bpm == 97 && s2.swing_on == 8 && s2.mono
            # old file (no swing_version) with triplets and 0.5 -> exact triplets
            d = DrumMachine.song_to_dict(preset("Blues: Jump / Swing"))
            d["swing"] = 0.5; delete!(d, "swing_version")
            @test DrumMachine.song_from_dict(d).swing == 2 / 3
            d["swing_version"] = 2
            @test DrumMachine.song_from_dict(d).swing == 0.5
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
