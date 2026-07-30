# Fermata

A small language model that composes multi-part music and engraves it as
sheet music. Elixir/Nx/Axon, with backbones from
[Edifice](../edifice) (a local path dep).

The point of the project is to learn how LLMs work by building one where
the "language" is music notation. The first concrete deliverable is a
**playable clarinet + cello duet** — so "does it engrave to a page two
humans can read and perform" is the acceptance test, not perplexity.

`PLAN.md` is authoritative for design decisions and phases.
`whats-next.md` is the running session handoff — read both before
proposing work.

## Invariants that will bite you

**Token ids are append-only.** Ids 0..526 are frozen: the packed corpus
shards on disk and any trained embedding table index them positionally.
`Vocab.tokens/0` builds a `phase_0` block and then appends. Instrument
tokens live *inside* that block, so new instruments go in
`Instruments.@added` (which the vocab appends at the very end), never in
`@phase_0`. Same for any new token kind. Adding a token in the middle
shifts every id after it and silently corrupts both the corpora and any
checkpoint — it raises nothing and shows up as mysteriously bad samples.

    After ANY vocab change: mix fermata.corpus bach_chorales
    must still report exactly 210,974 tokens.

**The IR is concert pitch.** What the model generates, and everything in
`Fermata.Score`, sounds as written. Producing a transposing instrument's
part is a *rendering-time* step (`Transpose.to_written/2`), deliberately
outside the token stream; `Part.transpose` is presentation metadata the
tokenizer ignores. Do not teach the model written pitch.

**Same-voice events are contiguous within a measure.** Multi-voice
measures store events grouped by voice, in order of first appearance.
`Measure.voice_groups/1` is the single place that invariant is read; the
tokenizer and MusicXML writer both depend on it for exact round-trips.
Both parsers produce grouped output — keep it that way.

**Duration is written value + tuplet ratio, stored separately.** A
triplet eighth is `duration: {:eighth, 0}, tuplet: {3, 2}`. This mirrors
notation and MusicXML (`<time-modification>` belongs to the note, not to
its `<type>`). Sounding length is always
`Duration.divisions_for(duration, tuplet)` — never `divisions_for/1`
alone, which silently gives the unscaled value.

**Refuse rather than mangle.** Parsers return typed errors
(`{:error, {:unsupported_tuplet, 11}}`) for anything they cannot
represent faithfully, and corpus ingestion counts them. Do not round a
duration or drop a voice to make a file parse. `Duration.exact?/2` is
how you check before committing to an arithmetic path that would raise.

## Domain vocabulary

Kern conventions trip people up, so these three are kept distinct:

- **spine/column** — one tab-separated field in a kern file. Columns
  come and go via `*^` (split) and `*v` (merge).
- **part** — one instrument/staff. Fixed at the `**kern` header.
- **voice** — an independent rhythmic stream inside a part, created by
  `*^`. Divisi does not create a part.

Kern lists spines low-to-high (bass leftmost); the parser reverses so
part 0 is the top voice, matching MusicXML/IR convention.

`Fermata.Pitch` uses two coordinate systems on purpose: **chromatic**
(MIDI number — how high it sounds, loses spelling) and **line of
fifths** (how it is spelled, octave-free). A major key's line-of-fifths
position *is* its `<fifths>` number, which is why transposing a key
signature and transposing a pitch are the same operation.

`Duration.divisions/0` is 20160 = 64 × lcm(3,5,7,9). The 64 covers
binary values down to a double-dotted 64th; the LCM covers thirds,
fifths, sevenths and ninths of a beat. Supporting 11- or 13-tuplets is
one edit to `@tuplet_actuals` at a proportionally larger constant.

## Numerics policy

Hard-won, do not relax without a smoke test:

- **Loss math is always f32**, whatever the network computes in.
  `Model.loss/2` casts at its entry point.
- Norm layers are excluded from the bf16 downcast.
- Axon's dynamic loss scaler *applies* overflowed grads and only detects
  infinity, not NaN. Smoke-test bf16 on the exact backbone before any
  long run (`test/fermata/model_smoke_test.exs`).
- `Polaris.Updates.apply_updates/2` is broken under nx 0.13 (its
  optional `state` defaults to `nil`, which jit argument traversal
  rejects). Use the hand-rolled tree `Nx.add` in the smoke test.

## Commands

    mix test                              # full suite, ~3s on CPU
    mix test --stale                      # after targeted changes
    mix fermata.corpus                    # list sources + status
    mix fermata.corpus bach_chorales      # download, ingest, stats
    mix fermata.instruments --transposing # browse the registry
    mix run examples/render_kern.exs f.krn   # kern -> tokens -> engraved PDF
    mix run examples/duet.exs             # clarinet + cello duet

Generated renders land in `examples/out/`; corpora and packed shards in
`data/`. Both are gitignored and regenerate in seconds — never commit
them.

## Conventions

- **Never pipe long-running command output through `head`/`tail`/`grep`.**
  Redirect to a file, then read the file. Applies to `mix test` and to
  corpus ingestion.
- **Elixir, not Python**, for scripts and one-off analysis — including
  throwaway ones. Use `mix run script.exs` or the Edit tool.
- Prefer targeted test files over the full suite when iterating.
- Property tests (`test/support/generators.ex`) generate multi-voice
  measures and tuplets. When adding an IR feature, extend the generators
  too — the round-trip properties are the cheapest place to catch a
  writer/parser asymmetry.
- Verify notation changes by **looking at the engraved output**, not
  just the XML. `rsvg-convert` a page to PNG and read it. Several bugs
  here (divisi alignment, tuplet bracket grouping) were only visible on
  the page.
- No emojis. Ask before non-obvious choices.

## Environment

Elixir 1.18.4, nx 0.13 / axon 0.8 / polaris 0.1. `exla` is commented out
in `mix.exs` until the RTX 5090 box — when enabling it, export
`XLA_TARGET=cuda12` **explicitly**, because autodetection silently falls
back to CPU. Always `Axon.build(model, compiler: EXLA)`; uncompiled call
overhead is ~100×.

Renderers `verovio`, `lilypond` and `rsvg-convert` are installed and
working. Verovio emits multi-page output as `score_001.svg`
(`Render.read_pages` handles the naming). MuseScore headless is avoided
— it needs Xvfb.

## Sharing edifice with exphil

Fermata and exphil both path-depend on `../edifice`, and both are under
active development at once. Working agreement:

- `~/git/edifice` (main) is the stable shared dep. It stays green:
  nothing lands on main unless `mix test` passes in **both** fermata and
  exphil.
- Edifice feature work happens in the `~/git/edifice-dev` worktree (or
  additional worktrees), never by leaving `../edifice` dirty — a dirty
  shared dep makes downstream failures ambiguous about which project
  broke.
- Fermata's edifice surface is small (`Generate.build_lm`,
  `MixedPrecision`, `Checkpoint`) and guarded by
  `test/fermata/model_smoke_test.exs` — run it after any edifice merge.
  If exphil-driven churn ever bites, pin fermata to a git dep (exphil's
  `EDIFICE_REPO` fallback in its mix.exs is the pattern to copy).
