using Test, DrumMachine
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
        @test sum(step_samples(ht, k) for k in 0:23) ≈ 4 * 60 / 80 * SR   # Swing wirkt nicht auf Triolen
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
            @test f.grid[:, 1:g.steps-n] == g.grid[:, 1:g.steps-n]     # Groove davor bleibt
            @test any(!iszero, f.grid[:, g.steps-n+1:g.steps])
            @test f.grid[4, g.steps-n+1:g.steps] == zeros(UInt8, n)     # HiHat pausiert im Fill
        end
        @test make_fill(g, 4, 1).grid == make_fill(g, 4, length(FILL_STYLES) + 1).grid
        @test row_string(make_fill(g, 4, 2), 7) == ".............x.."             # Tom-Abgang: Tom in der Mitte
        short = pattern_from_rows(Dict("Snare" => "X.X."))
        @test make_fill(short, 4, length(FILL_STYLES)).steps == 4                 # Fill länger als Pattern
    end

    @testset "Spur-Effekte" begin
        D = DrumMachine
        q = D.design!(D.Biquad(), :low, 120, 6)                 # +6 dB Tiefen → 50-Hz-Sinus ~ doppelt so laut
        y = [D.process(q, Float32(sinpi(2 * 50 * k / SR)), 0f0)[1] for k in 1:SR]
        @test 1.8 < maximum(abs, y[SR÷2:end]) < 2.1
        q = D.design!(D.Biquad(), :high, 5000, 6)               # Höhen-Shelf lässt Bass unverändert
        y = [D.process(q, Float32(sinpi(2 * 50 * k / SR)), 0f0)[1] for k in 1:SR]
        @test 0.97 < maximum(abs, y[SR÷2:end]) < 1.03
        s = preset("Rock: 8tel")
        y0 = render_song(s, bp; repeats = 1)
        s2 = copy(s); s2.tracks[2].eq_midf = 2000                # nur Frequenz geändert: kein Effekt
        @test render_song(s2, bp; repeats = 1) == y0
        D.set_mod!(s2.tracks[4], "Flanger"); s2.tracks[4].mod_mix = 1
        s2.tracks[1].eq_low = 4.5; D.set_mod!(s2.tracks[2], "Chorus")
        y1 = render_song(s2, bp; repeats = 1)
        @test y1 != y0 && maximum(abs, y1) < 0.98
        mktempdir() do dir
            path = joinpath(dir, "fx.toml")
            save_song(path, s2)
            txt = read(path, String)
            @test occursin("mod = \"Flanger\"", txt) && occursin("eq_low = 4.5", txt)
            @test count("eq_low", txt) == 1                       # nur Spuren mit Effekt
            t = load_song(path).tracks
            @test t[4].mod == 3 && t[4].mod_mix == 1 && t[4].mod_fb ≈ 0.6
            @test t[2].mod == 2 && t[1].eq_low == 4.5 && t[3].mod == 1
            @test render_song(load_song(path), bp; repeats = 1) ≈ y1
        end
    end

    @testset "Datei-Dialog" begin
        mktempdir() do bin
            fake = joinpath(bin, "zenity")
            withenv("PATH" => bin * ":" * ENV["PATH"]) do
                write(fake, "#!/bin/sh\necho /x/y.toml\n"); chmod(fake, 0o755)
                @test DrumMachine.pick_song_file() == "/x/y.toml"
                write(fake, "#!/bin/sh\nexit 1\n")
                @test DrumMachine.pick_song_file() == ""                  # Abbrechen
            end
        end
    end

    @testset "Timing" begin
        s = preset("Rock: 16tel"); s.bpm = 120
        @test sum(step_samples(s, k) for k in 0:15) ≈ 2SR      # 4 Viertel à 0,5 s
        s.swing = 0.66
        @test step_samples(s, 0) > step_samples(s, 1)
        @test sum(step_samples(s, k) for k in 0:15) ≈ 2SR      # Swing ändert die Taktlänge nicht
        # Auto: 8tel-Groove swingt auf 8tel, 16tel-Groove auf 16tel
        p8 = pattern_from_rows(Dict("HiHat" => "x.x.x.x.x.x.x.x."))
        p16 = pattern_from_rows(Dict("HiHat" => "xxxxxxxxxxxxxxxx"))
        on8 = cumsum([step_samples(s, k, p8) for k in 0:15])
        @test on8[2] / (on8[4] - on8[2]) ≈ 0.66 / 0.34          # "+" rutscht nach hinten
        @test step_samples(s, 0, p16) > step_samples(s, 1, p16)
        s.swing_on = 8
        @test step_samples(s, 0, p16) == step_samples(s, 1, p16)
        @test sum(step_samples(s, k, p16) for k in 0:15) ≈ 2SR
        # Triolen-Raster: Standard = exakte Triolen, Swing verschiebt die dritte Triole
        t = Song(bpm = 120, steps_per_beat = 3)
        @test t.swing == 2 / 3
        @test step_samples(t, 0) ≈ step_samples(t, 1) ≈ step_samples(t, 2)
        t.swing = 0.75
        @test step_samples(t, 0) + step_samples(t, 1) ≈ 0.75 * 0.5SR
        @test sum(step_samples(t, k) for k in 0:11) ≈ 2SR
    end

    @testset "Export" begin
        s = preset("Rock: 8tel")
        y = render_song(s, bp; repeats = 1, countin = 1)
        @test size(y, 2) == 2
        @test size(y, 1) >= round(Int, song_seconds(s; repeats = 1, countin = 1) * SR) - 1
        @test maximum(abs, y) <= 1
        # Erster Schlag liegt nach dem Einzähler
        bar = round(Int, song_seconds(s; repeats = 1, countin = 0) / length(s.chain) * SR)
        @test maximum(abs, y[1:bar÷8, :]) > 0.01          # Einzähler-Klick hörbar
        # Mute wirkt im Export
        s2 = preset("Rock: 8tel"); foreach(t -> t.mute = true, s2.tracks)
        @test maximum(abs, render_song(s2, bp; repeats = 1, countin = 0)) < 1e-3
        mktempdir() do d
            # Dateinamen nur ASCII (Roland TD-27 u. a.)
            @test ascii_filename("Übung: Größe ä ö ü ß – Café.wav") == "Uebung_ Groesse ae oe ue ss _ Cafe.wav"
            @test all(isascii, ascii_filename("Funk: What-Is-Hip-Stil (Tower of Power).wav"))
            f = export_wav(joinpath(d, "Grüße Ölfaß.wav"), s, bp; repeats = 1)
            @test basename(f) == "Gruesse Oelfass.wav" && isfile(f)
            # Standard-WAV: RIFF/WAVE, fmt (16 Byte, PCM), data – sonst nichts
            b = read(f)
            @test b[1:4] == b"RIFF" && b[9:12] == b"WAVE" && b[13:16] == b"fmt "
            @test reinterpret(UInt32, b[17:20])[1] == 16
            @test reinterpret(UInt16, b[21:24]) == [1, 2]                  # PCM, Stereo
            @test reinterpret(UInt32, b[25:28])[1] == 44100
            @test reinterpret(UInt16, b[35:36])[1] == 16                   # Bit
            @test b[37:40] == b"data" && 44 + reinterpret(UInt32, b[41:44])[1] == length(b)
            f = export_wav(joinpath(d, "a.wav"), s, bp; repeats = 1, mono = true)
            @test size(DrumMachine.WAV.wavread(f)[1], 2) == 1
            f = export_wav(joinpath(d, "b.wav"), s, bp; repeats = 1)
            @test size(DrumMachine.WAV.wavread(f)[1], 2) == 2
            # Mono wirkt schon beim Rendern (= Live-Wiedergabe): beide Kanäle identisch
            sm = copy(s); sm.mono = true
            ym = render_song(sm, bp; repeats = 1)
            @test ym[:, 1] == ym[:, 2]
            ys = render_song(s, bp; repeats = 1)
            @test ys[:, 1] != ys[:, 2]
        end
    end

    @testset "Sample-Onsets" begin
        # Kein Sample darf später als 2 ms nach Beginn anschlagen (sonst wackelt das Timing)
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
        # nie zweimal hintereinander dieselbe Aufnahme, solange es mehr als eine gibt
        mk() = DrumMachine.Sample(rand(Float32, 10))
        layers = [[mk(), mk()], [mk(), mk(), mk()], [mk()]]
        rng = DrumMachine.MersenneTwister(1)
        prev = DrumMachine.Sample(Float32[])
        for _ in 1:200
            s = DrumMachine.pick_sample(rng, layers, 2, prev)
            @test s !== prev
            prev = s
        end
        # Export ist reproduzierbar (geseedeter Zufall)
        s = preset("Funk: Ghost Notes")
        @test render_song(s, bp; repeats = 2) == render_song(s, bp; repeats = 2)
    end

    @testset "Speichern/Laden" begin
        s = preset("Funk: Ghost Notes"); s.tracks[2].mute = true; s.bpm = 97; s.swing_on = 8; s.mono = true
        mktempdir() do d
            f = save_song(joinpath(d, "x.toml"), s)
            s2 = load_song(f)
            @test s2.patterns[1].grid == s.patterns[1].grid
            @test s2.tracks[2].mute && s2.bpm == 97 && s2.swing_on == 8 && s2.mono
            # Alte Datei (ohne swing_version) mit Triolen und 0.5 → exakte Triolen
            d = DrumMachine.song_to_dict(preset("Blues: Jump / Swing"))
            d["swing"] = 0.5; delete!(d, "swing_version")
            @test DrumMachine.song_from_dict(d).swing == 2 / 3
            d["swing_version"] = 2
            @test DrumMachine.song_from_dict(d).swing == 0.5
        end
    end
end
