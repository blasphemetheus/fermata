# Project Plan: Small Language Model for Multi-Part Music Composition

**Status:** planning · **Placeholder name:** **Fermata** (chosen)
**Target hardware:** RTX 5090 (32GB) at home; laptop-friendly dev while traveling
**Stack:** Elixir · Nx · Axon · EXLA · Edifice

## 1. The core design decision: generate scores, not MIDI

The single most important finding from research: **since sheet music is the
deliverable, the model should generate score-level tokens directly** (notation:
barlines, voices, key signatures, spelled pitches), with MIDI as a derived
export. The alternative — generating performance MIDI and converting to
notation — requires solving four hard problems at output time (rhythm
quantization, voice separation, enharmonic spelling, transposing instruments),
each an active research area on its own.

This is validated by the strongest recent systems: **NotaGen** (IJCAI 2025,
516M params) generates interleaved ABC notation and beat MIDI-token models in
A/B tests on classical music; it exports ABC → MusicXML → engraved score
directly.

## 2. Why a small model is the right call (not a compromise)

- **SymphonyGen (2026): 124M params beat NotaGen (516M) and SymphonyNet on
  subjective orchestral musicality.** Representation and architecture dominate
  parameter count in this domain.
- MetaScore's 87M models scored ~4/5 on coherence/arrangement in listening tests.
- NotaGen itself ships 110M and 244M variants.
- MuPT's "SMS Law": for symbolic music, extra epochs over a domain corpus buy
  more than they do in text — favors small-model + many-epochs, exactly what a
  single 5090 supports.
- Off-the-shelf LLMs are *bad* at symbolic music (near-random on music
  reasoning), and fine-tuning general LLMs on music degrades their general
  ability — training from scratch on domain tokens loses nothing.

**Target: 30M → 120M → ~250M parameters across phases.** All train comfortably
in bf16 + AdamW on 32GB.

## 3. Representation & tokenization

### Canonical intermediate representation (IR)
Parse source formats (MusicXML, kern, ABC) into one Elixir struct-based score
IR: `Score → Part → Measure → Voice → {Note|Chord|Rest|Tuplet}` plus key/time
signatures, clefs, dynamics, ties/slurs. Everything downstream (tokenizer,
MusicXML writer, augmentation) works off the IR. This is the project's real
foundation and is fully testable on a laptop.

### Token scheme: measure-interleaved multi-part tokens
Follow the NotaGen/MuPT insight that **cross-voice measure alignment is the
dominant failure mode** of naive multi-part text formats. All parts of measure
*N* appear together before any of measure *N+1*:

```
<piece key=G minor time=4/4> <parts: violin1 violin2 viola cello>
<m1> <p:vln1> notes… <p:vln2> notes… <p:vla> … <p:vc> … <m2> …
```

- Pitches are **spelled** (F#4 vs Gb4 distinct tokens) — notation-grade output
  for free, and the vocabulary stays small (~2–3K tokens: ~35 pitch-classes ×
  8 octaves, durations, ~130 instruments, structural/dynamic tokens).
- Durations are notated values (quarter, dotted-eighth, triplet-eighth), not
  ticks.
- **No vanilla BPE.** SAGE-Music (2025) found BPE degrades badly in
  multi-track settings despite single-track piano gains. Start with the raw
  vocab; revisit music-specific merging (SymphonyNet-style) only if sequence
  length forces it.
- Conditioning tokens at sequence start: instrumentation, key, meter, period/
  composer-style (NotaGen showed period–composer–instrumentation prompts work
  well) — controllability without any text encoder.

### Context budget
Chorales/quartet movements: ~1–4K tokens. Romantic chamber works: ~8–16K.
A full symphony movement: 50K+ in fine-grained schemes — **no published model
fits one in context.** Plan: standard 4–8K context through Phase 2; for
orchestral (Phase 3) use either a linear-complexity backbone (Mamba/hybrid —
already in Edifice) or section-level continuation (generate movement in
overlapping windows conditioned on a running summary/skeleton). SymphonyGen's
Bar×Track×Event hierarchical decomposition is the research-grade option if
needed.

## 4. Data (staged by license and quality)

| Stage | Corpus | Size | License | Role |
|---|---|---|---|---|
| Core | **PDMX** `no_license_conflict` | 222,856 MusicXML scores, ~6,250h | PD/CC0 only | Main training set. Caveat: >90% has <5 parts |
| Gold multi-part | **OpenScore String Quartets** | 100+ full quartets | CC0 | The best true 4-part contrapuntal data anywhere |
| Gold multi-part | **OpenScore Lieder** | ~1,300 songs | CC0 | Voice+piano, 2–3 real parts |
| Gold classical | **KernScores/humdrum-data** | 26K curated files incl. 82 Haydn symphonies, Beethoven quartets, Brandenburgs, 370+ Bach chorales | PD | Fine-tune + eval; Verovio renders kern natively |
| Small/clean | **Mutopia** | 2,124 pieces | PD/CC | Native LilyPond source |
| Orchestral (⚠ license) | **SOD** | 5,743 songs, 357h | murky (subscription-site scrapes) | Orchestral fine-tune, research-only |
| Orchestral (⚠ license) | **SymphonyNet dataset** | 46,359 symphonic MIDIs | unclear | Same; MIDI-grade only, no notation semantics |

A **PDMX + OpenScore + KernScores + Mutopia** stack (~260K scores) is fully
copyright-clean — a genuinely defensible "trained only on public domain"
story, rare in this space. The orchestral corpora are the only license
compromise and can be quarantined to an optional fine-tune.

Skip for now: Lakh/GigaMIDI/Aria-MIDI (performance MIDI, wrong modality),
MidiCaps (text conditioning out of scope).

## 5. Architecture & training (Edifice/Nx)

- **Backbone:** `Edifice.build(:decoder_only, ...)` (GQA+RoPE+SwiGLU,
  LLaMA-style) as baseline; benchmark against Edifice SSM/linear backbones
  (`mamba`, `samba`, `zamba`, `griffin`, `retnet`, `gla`) — same
  swappable-backbone methodology as ExPhil, and it dogfoods Edifice.
  **XLA has no usable flash attention**, so attention is O(seq²) activation
  memory — at 100M params, batch 8 × seq 2048 already hits ~19GB. Edifice's
  40+ subquadratic backbones neutralize exactly this constraint; they are a
  strategic advantage here, not a curiosity.
- **Generation:** `Edifice.Serving.Generate.build_lm/1` +
  `generate_simple/3` (full re-run each step — correct) and `sampling.ex`
  (greedy/temp/top-k/top-p — correct and tested). See §5.1 for what needs
  fixing first.
- **Training:** Axon.Loop + `Edifice.MixedPrecision` (bf16 compute, f32
  master weights, **loss math always f32** — the exphil NaN incident) +
  `Edifice.Checkpoint.save_loop_state/resume`. Pre-tokenize the corpus to
  packed binary shards once (pattern: exphil's `training_shards.ex`, or a
  flat train.bin + `:file.pread/2` scatter-gather reads wrapped in
  `Stream.repeatedly/1`).
- **Tokenizer:** custom, written in Elixir against the IR — the vocab is
  constructed by enumeration, not learned, so no BPE trainer needed. (The
  `tokenizers` hex package *can* train BPE if ever wanted.)

### 5.1 Known Edifice/Axon gaps to fix or route around (from repo audit)

Edifice fixes (upstream contributions, all bounded):
1. **`build_lm/1` has no trainable token embedding** — input is continuous
   vectors; the embedding table currently lives outside `Axon.ModelState`
   and never trains. ~5-line fix (`Axon.embedding` prepend). **Mandatory,
   do first.**
2. **`generate/3`'s "cached" decode path is semantically wrong** — embeds
   the new token into an otherwise-zeros buffer, losing all prior context.
   Only `generate_simple/3` is correct; tests never compare the two. Use
   `generate_simple` until KV-cache decoding is actually implemented
   (`blocks/kv_cache.ex` exists but is wired to nothing; Bumblebee's
   `Text.Generation`/`Layers.Decoder` is a viable template, ~1–2 days
   leaning on its private helpers).
3. **`Training.remat/2` gradient checkpointing is a no-op** (identity
   wrapper, no `Nx.Defn.checkpoint`) — don't budget memory around it.

Axon/Polaris route-arounds:
- **No gradient accumulation** (removed from Axon in 2024) — hand-roll via
  custom step_fn if needed; at ≤250M params on 32GB, likely unnecessary.
- **LR warmup:** Polaris has no warmup/join, and `linear_decay` ignores
  `init_value` (returns a bare 0–1 multiplier). Hand-compose
  warmup→cosine with `Nx.select`.
- **AdamW weight decay is `:decay`** and applies to biases/norms too (no
  param masking).
- **Resume is epoch-granular** (stream position not saved; `epochs:` on
  resume re-runs the last epoch) — prefer `iterations:`-defined epochs on
  an infinite replayable stream.
- **Loss scaling caveats:** dynamic scaler still *applies* overflowed
  grads and never detects NaN (checks infinity only). Smoke-test bf16 on
  the exact backbone for a few thousand steps before any long run.
- **`Polaris.Updates.apply_updates/2` is broken under nx 0.13** — its
  optional `state` arg defaults to `nil`, which nx 0.13's jit argument
  traversal rejects (`Nx.LazyContainer` not implemented for nil).
  Found empirically by the Phase 0 smoke test; use a hand-rolled tree
  `Nx.add` (see `test/fermata/model_smoke_test.exs`) or pass an explicit
  third argument.
- **Upgrade Edifice deps to nx/exla 0.13** — a 5090-specific runtime_call
  crash (nx #1687, reported on this exact stack) was fixed in exla 0.12.
- Always `Axon.build(model, compiler: EXLA)` — uncompiled call overhead
  is ~100×.

### 5.2 Throughput & feasibility (5090, derived estimates)

100M params ≈ 6e8 FLOPs/token. Expect **30–60k tok/s** in Axon/XLA
(10–20% MFU without flash attention; PyTorch reference would be
125–155k). Chinchilla-optimal 2B tokens → **~10–16 hours**. Training
state at 100M ≈ 3.2GB; activations dominate. Entirely feasible; the whole
plan's schedule hinges on one number, so **run
`bench/training_throughput.exs` on the 5090 early** to replace estimate
with measurement.

Context: the largest published from-scratch Axon transformer is ~11M
params, trained on CPU, in 2023. A 100M+ run on modern EXLA would be
frontier territory for the Elixir ML ecosystem — publishable/blog-worthy
on its own.
- **Eval:** held-out perplexity per corpus + CLaMP-2 score via a small Python
  sidecar (the one acceptable Python use, mirroring the libmelee precedent) +
  render-and-listen. Note: perplexity and Fréchet Music Distance are known to
  disagree; CLaMP + human listening is the field's standard.
- **Later quality lever:** CLaMP-DPO (preference pairs scored by CLaMP-2
  similarity — no human annotation). This is what pushed NotaGen past MuPT.

## 6. Sheet music output pipeline

```
tokens → IR → MusicXML writer (Elixir, ~300 LOC for the needed subset)
                    ├→ Verovio CLI (port) → SVG → rsvg-convert → PDF   [primary]
                    ├→ LilyPond (port) → print-quality PDF              [final output]
                    └→ Verovio/MuseScore → MIDI                         [playback export]
```

- **There is no MusicXML/ABC/LilyPond library on hex** — the MusicXML writer
  is ours to build (straightforward: `score-partwise` via XmlBuilder/Saxy).
- **Verovio** is the primary renderer: single static binary, no display
  server, reads MusicXML/kern/ABC, emits SVG + MIDI. LilyPond for engraving
  quality when it matters.
- Avoid MuseScore CLI unless import breadth is needed — MuseScore 4 headless
  requires Xvfb-in-Docker gymnastics.
- Hex MIDI packages (`midiex` etc.) are realtime-I/O only, not file I/O — but
  we don't need MIDI parsing if we go score-native; MIDI is emitted by the
  renderer.

## 7. Phases

**Phase 0 — Foundations (laptop-friendly, do on vacation):**
mix project; score IR; MusicXML *parser* (Saxy) + *writer*; kern parser;
tokenizer + detokenizer with round-trip property tests
(`parse → tokenize → detokenize → write → re-parse == original`);
Verovio/LilyPond ports. Also laptop-friendly: the Edifice `build_lm/1`
embedding fix + bf16 CPU smoke tests (§5.1). Exit: hand-written token
sequence renders to a correct PDF of a Bach chorale.

**Phase 0.5 — First day home:** `XLA_TARGET=cuda12` env, upgrade Edifice
to nx/exla 0.13, run `bench/training_throughput.exs` on the 5090 →
replace §5.2's estimated tokens/sec with a measured number.

**Phase 1 — Chorale/duet model (~30M params):**
Train on Bach chorales + OpenScore Lieder + PDMX small-ensemble subset.
Exit: unconditioned + key/meter-conditioned 4-part chorales that a musician
reads as competent voice-leading. Proves the entire loop end-to-end.

**Phase 2 — Chamber music (~120M, 8K context):**
Full PDMX `no_license_conflict` + OpenScore Quartets + KernScores.
Instrumentation/style conditioning. Exit: multi-movement duets–quintets with
coherent per-instrument writing (ranges, idioms).

**Phase 3 — Orchestral (stretch):**
SOD/SymphonyNet fine-tune (license-quarantined); long-context strategy
(hybrid SSM backbone and/or windowed continuation); transposing-instrument
handling in the writer. Exit: a listenable, readable short symphonic movement.

**Phase 4 — Quality & polish:**
CLaMP-DPO; sampling controls (temperature per token class); maybe a small
Phoenix LiveView front end (paste a prompt, get engraved SVG + playback).

**Scope cuts (explicit non-goals for v1):** audio generation, free-text
conditioning (attribute tokens instead), performance/expressive-MIDI modeling,
lyrics, and MIDI *input* parsing.

## 8. Name candidates

Sibling projects are ExPhil and Edifice — one-word, evocative, not "Ex"-cute.

| Name | Why |
|---|---|
| **Tutti** | "everyone plays" — the ensemble/multi-part identity in five letters; short module name |
| **Sinfonia** | Bach's 3-part inventions *and* a small symphony — spans duet→symphony scope exactly |
| **Counterpoint** | the craft of independent simultaneous voices = literally the model's job |
| **Ripieno** | the full ensemble in a concerto grosso; obscure-cool like "Edifice" |
| **Partita** | multi-movement suite; pretty word; `Partita.compose/2` reads well |
| **Fermata** | memorable, musical; weaker semantic tie |
| **Stretto** | overlapping fugue entries — voices in tight imitation; sharp and short |
| **Cantus** | from *cantus firmus*, the voice others are composed against |

Recommendation: **Tutti** (best meaning-to-length ratio) or **Sinfonia**
(if the symphonic ambition should be in the name). Check hex.pm availability
before committing.

## 9. Open questions

1. ~~Verify Nx/EXLA on Blackwell~~ **Resolved:** xla 0.10.0 cuda12 prebuilts
   ship native sm_120 cubins (verified in elixir-nx/xla PR #127 — your own
   PR). Requirements: CUDA ≥12.1, cuDNN ≥9.8. **Trap:** `XLA_TARGET`
   autodetects via `nvcc --version` and silently falls back to CPU if nvcc
   isn't on PATH — set `XLA_TARGET=cuda12` explicitly. Upgrade to
   exla ≥0.12 for the 5090 runtime_call fix.
2. ABC output as a bonus export? (xml2abc exists; low priority.)
3. Whether Phase 3 uses hierarchical decoding (SymphonyGen-style) vs. long-
   context hybrid backbone — decide with Phase 2 perplexity-vs-length data.
4. Upstream the Edifice fixes (§5.1) as their own PRs vs. patching in-project
   first — they benefit ExPhil too.

## Key references

NotaGen arXiv:2502.18008 · SymphonyGen arXiv:2604.25498 · MuPT
arXiv:2404.06393 · SAGE-Music arXiv:2510.00395 (BPE warning) · SymphonyNet
arXiv:2205.05448 · PDMX arXiv:2409.10831 · OpenScore Lieder/StringQuartets
(github.com/OpenScore) · KernScores kern.humdrum.org · Verovio
rism.digital/verovio · MidiTok (tokenization reference) arXiv:2310.17202
