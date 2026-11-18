# AAC export (.m4a) through ffmpeg from FFMPEG_jll, e.g. to send examples via WhatsApp.
# Julia has no AAC encoder, so the audio is written to a temporary WAV and converted by ffmpeg.

using FFMPEG_jll: FFMPEG_jll

"True if ffmpeg (FFMPEG_jll) is available on this platform."
has_ffmpeg() = FFMPEG_jll.is_available()

"""
    save_aac(path, w; bitrate = 192, range = nothing) -> path

Writes `w` (or the frames in `range`) as AAC in an .m4a file using ffmpeg. 44.1/48 kHz and mono/
stereo are kept; other sample rates are converted to 44.1 kHz. `+faststart` puts the index at
the front of the file, which messengers and browsers need to start playback before the download
is complete. Errors (conversion failed) carry ffmpeg's message.
"""
function save_aac(path::AbstractString, w::Wave; bitrate::Integer = 192,
                  range::Union{Nothing,AbstractUnitRange} = nothing)
    has_ffmpeg() || error(L("ffmpeg ist auf dieser Plattform nicht verfügbar."))
    mkpath(dirname(abspath(path)))
    tmp = tempname() * ".wav"
    try
        save_wave(tmp, w; bits = 32, range)                  # float: no extra quantization step
        rate = w.fs in (44100, 48000) ? String[] : ["-ar", "44100"]
        cmd = `$(FFMPEG_jll.ffmpeg()) -y -hide_banner -loglevel error -i $tmp $rate -c:a aac -b:a $(bitrate)k -movflags +faststart $(String(path))`
        err = IOBuffer()
        p = Base.run(pipeline(ignorestatus(cmd); stdout = devnull, stderr = err))
        success(p) || error(L("ffmpeg-Fehler: {1}", strip(String(take!(err)))))
    finally
        rm(tmp; force = true)
    end
    return path
end
