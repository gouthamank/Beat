#!/usr/bin/env python3
"""Synced lyrics (.lrc) for a showcase song with vocals, from whisper.cpp's per-word timestamps.

whisper joins sung lines into one segment ("all alone again Wrapped up in this bed"); a new line starts at a
capitalised word, or after a pause. A line starting with "I" can't be told from one that only contains it, so those
stay joined for the hand correction. Its word timings are rough where a note is held, so a line starts at its first
word, pulled in when that word is stretched over seconds. The result is a draft: listen once and correct misheard
words by hand.

  brew install whisper.cpp   (and a model: https://huggingface.co/ggerganov/whisper.cpp, e.g. ggml-small.en.bin)
  afconvert -f WAVE -d LEI16@16000 -c 1 Audio/<song>.m4a /tmp/<song>.wav
  whisper-cli -m ggml-small.en.bin -f /tmp/<song>.wav -ojf -of /tmp/<song> -np
  python3 Design/Showcase/lyrics.py /tmp/<song>.json > Design/Showcase/Lyrics/<song>.lrc

With the real lyrics in a text file, one line per sung line, whisper only supplies the timing: each line takes the
time of its words in what whisper heard (matched word by word, so misheard words don't matter).

  python3 Design/Showcase/lyrics.py /tmp/<song>.json Design/Showcase/Lyrics/<song>.txt > Design/Showcase/Lyrics/<song>.lrc
"""
import difflib
import json
import re
import sys

# Capitalised but no line break: "I" and its contractions.
NOT_A_BREAK = {"I", "I'm", "I've", "I'll", "I'd"}
PAUSE = 1.5      # seconds of silence between words that start a new line
HELD = 2.0       # a first word longer than this is a held note or a guess; start near its end
LEAD = 0.4       # how far before the word's end such a line starts


def words(segment):
    """Tokens merged into words with start and end in seconds; whisper's special tokens dropped."""
    result = []
    for token in segment["tokens"]:
        text = token["text"]
        if text.startswith("[_"):
            continue
        start, end = token["offsets"]["from"] / 1000, token["offsets"]["to"] / 1000
        if text.startswith(" ") or not result:
            result.append({"text": text.strip(), "start": start, "end": end})
        else:
            result[-1]["text"] += text
            result[-1]["end"] = end
    return [w for w in result if w["text"]]


def lines(transcription):
    for segment in transcription:
        current = []
        for word in words(segment):
            bare = word["text"].strip(",.!?\"'()")
            # A lone word is never a line of its own ("2" then "AM, all alone again").
            breaks = len(current) > 1 and (
                (bare[:1].isupper() and bare not in NOT_A_BREAK)
                or word["start"] - current[-1]["end"] > PAUSE
            )
            if breaks:
                yield current
                current = []
            current.append(word)
        if current:
            yield current


def stamp(seconds):
    minutes, rest = divmod(max(seconds, 0), 60)
    return f"[{int(minutes):02d}:{rest:05.2f}]"


def is_lyric(word):
    """whisper marks sung lines with ♪ and fills gaps with [MUSIC], (upbeat music) or [BLANK_AUDIO]."""
    text = word["text"]
    return text != "♪" and not (text.startswith(("[", "(")) or text.endswith(("]", ")")))


def start_of(word):
    """When a line starting with `word` starts: its start, or near its end when the note is held."""
    return word["end"] - LEAD if word["end"] - word["start"] > HELD else word["start"]


def tokens(text):
    """Words to match on: lower case, apostrophes and punctuation dropped, digits apart from letters ("2am": 2, am)."""
    return re.findall(r"\d+|[a-z]+", text.lower().replace("'", ""))


WORD = 0.35      # a sung word's rough length, to place a line whose first words weren't heard right


def aligned(transcription, text):
    """The real lyrics' lines, each timed by its words' place in what whisper heard."""
    heard = []
    for segment in transcription:
        for word in words(segment):
            if is_lyric(word):
                heard += [(t, word) for t in tokens(word["text"])]
    sung = [line.strip() for line in text.splitlines() if line.strip()]
    wanted = [(t, i) for i, line in enumerate(sung) for t in tokens(line)]
    matcher = difflib.SequenceMatcher(None, [t for t, _ in wanted], [t for t, _ in heard], autojunk=False)
    match, heard_at = {}, {}
    for block in matcher.get_matching_blocks():
        for k in range(block.size):
            match[block.a + k] = heard[block.b + k][1]
            heard_at[block.a + k] = block.b + k
    times = []
    for i in range(len(sung)):
        positions = [p for p, (_, line) in enumerate(wanted) if line == i]
        found = next(((n, p) for n, p in enumerate(positions) if p in match), None)
        if found is None:
            times.append(None)    # placed between its neighbours below
        elif found[0] == 0:
            times.append(start_of(match[found[1]]))
        else:
            # Its first words weren't heard right ("Many moons" for "And it moved"): it starts with the first word
            # heard after the line before ended, when that line's last word was heard; else the matched word less the
            # words sung before it.
            estimate = match[found[1]]["start"] - found[0] * WORD
            last = positions[0] - 1
            if last in heard_at and heard_at[last] + 1 < len(heard):
                estimate = min(estimate, start_of(heard[heard_at[last] + 1][1]))
            times.append(estimate)
    # Unmatched lines go halfway between their neighbours; times never run backwards.
    for i, t in enumerate(times):
        if t is None:
            before = next((times[j] for j in range(i - 1, -1, -1) if times[j] is not None), 0)
            after = next((times[j] for j in range(i + 1, len(times)) if times[j] is not None), before + 2)
            times[i] = (before + after) / 2
    for i in range(1, len(times)):
        times[i] = max(times[i], times[i - 1] + 0.1)
    return list(zip(times, sung))


def main(path, text_path=None):
    transcription = json.load(open(path))["transcription"]
    if text_path:
        for start, line in aligned(transcription, open(text_path).read()):
            print(stamp(start) + " " + line)
        return
    for line in lines(transcription):
        line = [w for w in line if is_lyric(w)]
        if not line:
            continue
        print(stamp(start_of(line[0])) + " " + " ".join(w["text"].replace("♪", "").strip() for w in line))


if __name__ == "__main__":
    main(*sys.argv[1:3])
