using Test, DrumMachine
using DrumMachine: NTRACKS, SR, step_samples, MAXSTEPS

@testset "DrumMachine" begin
    kits = available_kits()
    @test any(k -> k.name == "BlackPearl", kits)
    @test kits[end].name == "Synth"
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
        ht = preset("Funk: Half-Time Shuffle (Purdie-Stil)")
        @test ht.steps_per_beat == 6 && ht.patterns[1].steps == 24
        @test sum(step_samples(ht, k) for k in 0:23) ≈ 4 * 60 / 80 * SR   # Swing wirkt nicht auf Triolen
        @test preset("Blues: Shuffle (12 Takte)").patterns[1].steps == 12
        p = pattern_from_rows(Dict("Snare" => "..o.X..x"))
        @test p.steps == 8
        @test row_string(p, 2) == "..o.X..x"
        @test parse_chain("1x3 2", 2) == [1, 1, 1, 2]
        @test parse_chain("1 5 2", 2) == [1, 2]
    end

    @testset "Timing" begin
        s = preset("Rock: 16tel"); s.bpm = 120
        @test sum(step_samples(s, k) for k in 0:15) ≈ 2SR      # 4 Viertel à 0,5 s
        s.swing = 0.66
        @test step_samples(s, 0) > step_samples(s, 1)
        @test sum(step_samples(s, k) for k in 0:15) ≈ 2SR      # Swing ändert die Taktlänge nicht
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
            f = export_wav(joinpath(d, "a.wav"), s, bp; repeats = 1, mono = true)
            @test filesize(f) > 44
        end
    end

    @testset "Speichern/Laden" begin
        s = preset("Funk: Ghost Notes"); s.tracks[2].mute = true; s.bpm = 97
        mktempdir() do d
            f = save_song(joinpath(d, "x.toml"), s)
            s2 = load_song(f)
            @test s2.patterns[1].grid == s.patterns[1].grid
            @test s2.tracks[2].mute && s2.bpm == 97
        end
    end
end
