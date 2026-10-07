#!/usr/bin/env python3
"""Local speech-to-text with faster-whisper (CTranslate2, int8, CPU).

Usage:
    fw_transcribe.py <audio> [model_dir|size] [lang] [options]

    # preferred: model already fetched as a directory (see fetch_fw_model.sh)
    fw_transcribe.py /tmp/vn.wav /tmp/models/fw-medium id

    # fallback: let huggingface_hub resolve the size (can be very slow / stall)
    fw_transcribe.py /tmp/vn.wav medium id

Prints "[start -> end] text" per segment on stdout, diagnostics on stderr.
Run it in the BACKGROUND -- the 600 s foreground cap kills long jobs and you
lose the buffered output. Then poll:
    sleep 300; tail -1 /tmp/vn.txt

    fw_transcribe.py in.ogg /tmp/models/fw-medium id --wav-out /tmp/vn.wav

Non-WAV inputs without --wav-out still go through faster-whisper's own PyAV
decoder. If that raises a signature TypeError, re-run with --wav-out so the
16 kHz mono WAV is loaded as a numpy array instead.
"""
import argparse
import subprocess
import sys
import time


def to_wav(src: str, dst: str) -> None:
    """16 kHz mono PCM -- what Whisper actually wants."""
    subprocess.run(
        ["ffmpeg", "-y", "-v", "error", "-i", src, "-ar", "16000", "-ac", "1",
         "-c:a", "pcm_s16le", dst],
        check=True,
    )


def load_wav_array(path: str):
    """Read 16 kHz mono 16-bit PCM WAV into a float32 numpy array.

    faster-whisper skips its own av/PyAV decode when handed an ndarray, which
    sidesteps PyAV API drift -- that path has died with
    ``TypeError: av.open() got an unexpected keyword argument 'metadata_errors'``
    when the installed PyAV and faster-whisper disagree about the signature.
    """
    import wave as _wave

    import numpy as np

    with _wave.open(path, "rb") as w:
        got = (w.getframerate(), w.getnchannels(), w.getsampwidth())
        if got != (16000, 1, 2):
            raise ValueError(
                f"{path} must be 16 kHz mono 16-bit PCM WAV "
                f"(got {got[0]} Hz, {got[1]} ch, {got[2] * 8}-bit) -- pass --wav-out"
            )
        pcm = w.readframes(w.getnframes())
    return np.frombuffer(pcm, dtype=np.int16).astype(np.float32) / 32768.0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("audio", help="input audio (ogg/opus/m4a/wav/...)")
    ap.add_argument("model", nargs="?", default="medium",
                    help="CTranslate2 model directory, or a size name (medium/large-v3/small)")
    ap.add_argument("lang", nargs="?", default="id",
                    help="source language; 'id' for Indonesian/Javanese code-mixed speech")
    ap.add_argument("--prompt", default=("Percakapan bahasa Indonesia dan Jawa. "
                                         "Topik: pendaftaran sekolah, biaya, beasiswa, "
                                         "buku, praktek, seragam, donatur."),
                    help="initial_prompt in the SOURCE language -- fixes proper nouns")
    ap.add_argument("--threads", type=int, default=6,
                    help="PHYSICAL cores; oversubscribing is slower on a loaded box")
    ap.add_argument("--beam", type=int, default=5)
    ap.add_argument("--no-vad", action="store_true")
    ap.add_argument("--keep-prev", action="store_true",
                    help="re-enable condition_on_previous_text (default OFF to avoid loop hallucination)")
    ap.add_argument("--wav-out", default=None,
                    help="convert input to 16 kHz mono wav here first (ogg/opus/m4a inputs)")
    ap.add_argument("--via-av", action="store_true",
                    help="let faster-whisper's PyAV decoder open the file itself (default: load "
                         "the WAV as a numpy array, immune to PyAV signature drift)")
    args = ap.parse_args()

    from faster_whisper import WhisperModel  # imported late so --help works without it

    audio = args.audio
    if args.wav_out:
        to_wav(audio, args.wav_out)
        audio = args.wav_out
    # Hand faster-whisper an ndarray for WAV input: it then skips its own av/PyAV
    # decode, which is the path that breaks on PyAV signature drift.
    if str(audio).lower().endswith(".wav") and not args.via_av:
        audio = load_wav_array(str(audio))
        print(f"[fw] loaded {args.audio} as numpy array "
              f"({audio.shape[0] / 16000:.1f}s, 16 kHz mono)",
              file=sys.stderr, flush=True)

    t0 = time.time()
    print(f"[fw] model={args.model} device=cpu compute=int8 "
          f"threads={args.threads} lang={args.lang}", file=sys.stderr, flush=True)
    model = WhisperModel(args.model, device="cpu", compute_type="int8",
                         cpu_threads=args.threads)
    print(f"[fw] model loaded in {time.time() - t0:.1f}s", file=sys.stderr, flush=True)

    segments, info = model.transcribe(
        audio,
        language=args.lang,
        beam_size=args.beam,
        vad_filter=not args.no_vad,
        vad_parameters=dict(min_silence_duration_ms=600),
        # OFF by default: long rambling voice notes collapse into "om, om, om" loops
        condition_on_previous_text=args.keep_prev,
        initial_prompt=args.prompt,
    )
    print(f"[fw] detected={info.language} p={info.language_probability:.2f} "
          f"dur={info.duration:.1f}s", file=sys.stderr, flush=True)

    n = 0
    for seg in segments:
        # flush per segment: output survives an external kill
        print(f"[{seg.start:7.2f} -> {seg.end:7.2f}] {seg.text.strip()}", flush=True)
        n += 1

    print(f"\n[fw] done. {n} segments, elapsed {time.time() - t0:.1f}s",
          file=sys.stderr, flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
