# Fermata

A small language model that composes multi-part music and hands you
engraved sheet music at the other end. Written in Elixir (Nx/Axon), with
neural backbones from [Edifice](https://github.com/blasphemetheus/edifice).

It exists to answer a question by building rather than reading: what is
actually going on inside a language model? Music notation makes an
unusually good "language" for that — it has grammar, long-range
structure, and multiple simultaneous voices, and when the model gets it
wrong you can *hear* the mistake instead of squinting at a loss curve.

The first target is a **playable clarinet + cello duet**. Not a
benchmark number — a page two people can put on music stands.

> **Status:** the full pipeline works end to end on real music. The
> model itself is **not trained yet** — that is the next phase. What
> exists today is everything around it: parsers, tokenizer, corpora, the
> transposition engine, and engraving.

## What it does today

```
Humdrum **kern  ─┐                                    ┌─→  MusicXML 4.0
                 ├─→  Score IR  ─→  tokens  ─→  IR  ─→ ┤
MusicXML        ─┘                (u16 ids)            └─→  SVG / PDF
                                                            (Verovio)
```

Round-trips are exact: parse a Beethoven quartet movement, tokenize it,
decode the tokens back, and you get the same score — tuplets, divisi,
ties and all.

**Corpora**, ingested to packed binary shards with one command:

| source | coverage | tokens |
|---|---|---|
| Bach chorales (370) | 370/370 (100%) | 210,974 |
| Beethoven string quartets (71) | 71/71 (100%) | 683,943 |

**An instrument registry** of 98 instruments, 58 of them transposing,
each carrying the one fact everything else derives from: its written →
sounding interval. Ask for a part on an A♭ clarinet or an E♭ alto sax
and the key signature, the pitches and the MusicXML `<transpose>`
declaration all follow.

## Quickstart

Requires Elixir ~> 1.18 and, for engraving,
[Verovio](https://github.com/rism-digital/verovio) plus `rsvg-convert`
(LilyPond optional).

Edifice is a **path dependency**, so clone the two as siblings:

```sh
git clone https://github.com/blasphemetheus/edifice.git
git clone https://github.com/blasphemetheus/fermata.git
cd fermata && mix deps.get && mix test
```

Turn a real Bach chorale into engraved sheet music:

```sh
mix run examples/render_kern.exs examples/chor001.krn
# -> examples/out/chor001.{musicxml,pdf} + chor001-1.svg
```

Arrange two of its voices as a duet, each player's part transposed into
the pitch they actually read:

```sh
mix run examples/duet.exs                                  # clarinet + cello
mix run examples/duet.exs examples/chor001.krn alto_sax cello
```

The clarinet part comes out in A major while the cello sits in G major —
different key signatures on the same page, which is exactly right, and
the quickest way to see that the transposition engine works.

Browse the instruments:

```sh
mix fermata.instruments --transposing
mix fermata.instruments clarinet --aliases
```

```
id         | name                  | written → sounding | C major becomes | range
-----------+-----------------------+--------------------+-----------------+---------------
clarinet   | Clarinet              | M2 down            | D major         | D3–A#6 (50–94)
clarinet_a | Clarinet in A         | m3 down            | Eb major        | C#3–A6 (49–93)
alto_sax   | Alto Saxophone in E♭  | M6 down            | A major         | C#3–G#5 (49–80)
```

(abridged — the real table also carries family and default clef)

Build a corpus (downloads, parses, tokenizes, reports coverage):

```sh
mix fermata.corpus                    # list sources
mix fermata.corpus bach_chorales      # ~seconds
```

## The design bet

**Generate scores, not MIDI.** Most music models predict performance
events — pitch, velocity, microsecond timing — and then need a second,
lossy step to guess at notation. Fermata predicts notation directly:
spelled pitches (F♯ and G♭ are different notes), notated durations
(a dotted quarter, not 480 ticks), and parts interleaved measure by
measure so that voices stay aligned locally.

That choice buys three things:

- **The output is already sheet music.** No transcription step to lose
  the composer's intent.
- **The vocabulary is small** — 613 tokens, enumerated rather than
  learned, so no BPE trainer and no tokenizer drift.
- **Errors are legible.** A wrong note is a wrong note on the page, not
  a smeared distribution over a piano roll.

The cost is that everything upstream has to be *right*: a parser that
silently rounds a triplet or drops a divisi voice poisons the training
data invisibly. So parsers here refuse rather than mangle — anything
that cannot be represented faithfully comes back as a typed error and is
counted in the corpus statistics.

`PLAN.md` has the full reasoning, including the fallback if this bet
underperforms.

## Layout

```
lib/fermata/
  score.ex          Score/Part/Measure/Note/Rest/Duration — the IR
  pitch.ex          spelled-pitch arithmetic; line of fifths
  interval.ex       {diatonic, chromatic} intervals
  transpose.ex      to_written / to_concert / by_interval / to_key
  instruments.ex    the registry: keys, clefs, ranges, aliases
  vocab.ex          the enumerated token vocabulary
  tokenizer.ex      IR <-> token ids, exact round-trip
  kern/parser.ex    Humdrum **kern, incl. divisi spine splits
  music_xml/        MusicXML 4.0 reader and writer
  corpus.ex         download -> parse -> packed u16 shards
  model.ex          Axon model + the bf16/f32 numerics policy
  render.ex         Verovio / LilyPond wrappers
```

## Testing

```sh
mix test          # 67 tests, 3 doctests, 2 properties — about 3s on CPU
```

The property tests generate random-but-valid scores (multi-voice
measures, tuplets, ties, chords) and assert exact round-trips through
both the tokenizer and MusicXML. They are the cheapest place to catch a
writer/parser asymmetry.

## Roadmap

- [x] Score IR, tokenizer, kern + MusicXML parsers, engraving
- [x] Corpus pipeline with coverage statistics
- [x] Divisi (multi-voice) and tuplets — both corpora now parse fully
- [x] Instrument registry and arbitrary transposition
- [ ] Measure training throughput on GPU
- [ ] Train the model (Phase 1)
- [ ] Instrument-conditioned, range-constrained sampling
- [ ] The duet, composed rather than arranged

## License

Not yet chosen. The corpora are downloaded at build time from their own
sources and are not redistributed here.
