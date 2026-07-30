<original_task>
Fermata: a small language model for composing multi-part music with engraved sheet-music output, built in Elixir/Nx/Axon/Edifice to learn LLMs by building one from scratch. USER'S REAL GOAL (stated 2026-07-27): learn about LLMs by making one where the "language" is music notation; first concrete deliverable is a playable CLARINET + CELLO DUET the user and their brother can perform. Explanations of LLM concepts matter as much as shipping. Explanatory output style active (★ Insight blocks).
</original_task>

<work_completed>
## Earlier sessions (3ef5f75, 4c8e3e1, d7b4c27)
Score IR, enumerated vocab, tokenizer (exact round-trip), MusicXML 4.0 writer+parser (Saxy), Humdrum kern parser, Verovio/rsvg render wrapper, model numerics rig (bf16 + f32 loss), SATB fixture, property tests. Phase 0 exit criterion met (real Bach engraved and visually verified). Corpus pipeline: `mix fermata.corpus <source>` → download (shallow git clone) → parse → tokenize → flat u16 LE tokens.bin + index.etf, with coverage/percentile stats.

## This session (ab750d0, 3ab75d7, ee077b9, 6902917, 7e7f24b)

1. **Edifice build_lm embedding fix** (upstream commit edifice 73704a4, PLAN.md §5.1 gap #1 CLOSED).
   - `Generate.build_lm` now prepends `Axon.embedding`; models take integer `"token_ids"` and the table lives in `Axon.ModelState`, so it TRAINS. Previously it was an `Nx.take` closure outside the model and never received gradients.
   - Mechanism: new `:input` override on `ModelBuilder.build_sequence_model`, the bottleneck ~40 sequence architectures share. `embedding: :external` preserves legacy float-input behavior; `build_lm` raises if an arch ignores the override.
   - Removed the semantically wrong "KV-cached" decode: `generate/3` (and `generate_stream`/`token_stream`) embedded only the newest token into an all-zeros buffer, so the model saw NO history. All paths now re-run the full padded sequence. Generation accepts raw token ids (`:pad_token`) when no `embed_fn` given.
   - Edifice deps upgraded nx/exla 0.11 → 0.13 (its lock was inconsistent with the committed `nx ~> 0.12`; exla ≥0.12 also needed for the 5090).
   - Fermata: edifice is now a path dep; `Model.build/1` takes `backbone: :builtin | <edifice arch atom>`; both expose `"token_ids"` → logits.

2. **Kern spine splits + companion spines** → Beethoven quartets 1/71 → 40/71.
   - `**dynam` and other non-kern spines ignored (was rejecting 67 files).
   - `*^`/`*v` divisi split/merge parsed as IR voices. Parser restructured around DYNAMIC COLUMNS: parts fixed at the `**kern` header, voices created by `*^` and retired by `*v`.
   - A voice entering mid-measure gets LEADING RESTS — MusicXML positions voices by accumulated duration, so without them a divisi entry lands on the wrong beat. Voices renumbered densely per measure.
   - Multi-voice threads through: IR (`Note`/`Rest` `voice`, `Measure.voice_groups/1`), tokenizer (`{:voice, n}`, voice 1 implicit so single-voice output is unchanged), MusicXML (`<voice>` + `<backup>`).
   - `*x`/`*+` still refused.

3. **Instrument registry + transposition** (the "prompt for an Ab clarinet / Eb alto sax" request).
   - `Fermata.Pitch` — spelled-pitch arithmetic in two coordinate systems: chromatic (sounding height) and LINE OF FIFTHS (spelling). A major key's line-of-fifths position IS its `<fifths>` number, so transposing a key signature is the same operation as transposing a pitch.
   - `Fermata.Interval` — `{diatonic, chromatic}`, zero-based so intervals add by addition; identical to MusicXML `<transpose>` children.
   - `Fermata.Transpose` — `to_written/to_concert` per instrument, `by_interval`, `to_key` (nearest/up/down), `out_of_range`. Moves pitches + key signature + `<transpose>` together. Preserves spelling (F# up m3 = A; Gb up m3 = Bbb). Keys outside -7..7 respelled enharmonically.
   - Registry: 98 instruments (32 frozen Phase 0 + 66 added), 58 transposing, each with written→sounding interval, family, clef, sounding range, aliases.
   - Fixed instrument identification: name lookup was exact-match only, so `*I"Cello` → `:voice` (roster said "Violoncello") and Humdrum `*I` codes were ignored entirely — which is why all 4 quartet parts read "Voice". Alias table now covers display names, abbreviations and `*I` codes, matched case/spacing/♭-spelling-insensitively.
   - `mix fermata.instruments` browses it (filters: `--family`, `--transposing`, name search, `--aliases`), including a "what concert C major becomes" column.
   - `examples/duet.exs` — arranges two chorale voices as a playable duet, any two registry instruments. VERIFIED by engraving: clarinet in A major over cello in G major, differing key signatures being the visual proof.

4. **Tuplets** → Beethoven quartets 40/71 → **71/71 (100%)**.
   - Decoding needs no table: a kern recip is the reciprocal of a whole note, so factoring N = 2^k × m (m odd) gives the tuplet directly — m is the actual-count, 2^k × normal the base type. 12 = 4×3 → triplet eighth; 40 = 8×5 → quintuplet 32nd; 112 = 16×7 → septuplet 64th.
   - **Divisions changed 32 → 20160** = 64 × lcm(3,5,7,9). 32 cannot express a third of a beat. 64 covers binary values down to a double-dotted 64th (previously the one unrepresentable duration); the LCM covers thirds/fifths/sevenths/ninths. 11- and 13-tuplets = one edit to `@tuplet_actuals` at a proportionally larger constant.
   - Written duration and ratio stored SEPARATELY, ratio on the event (mirrors MusicXML `<time-modification>`): a triplet eighth is `{:eighth, 0}` + `tuplet: {3, 2}`.
   - Tuplet EXTENTS are not stored, only ratios, so the writer recovers groups: accumulate consecutive same-ratio events, close the group once their sounding total is itself a plain written value. Correctly splits six triplet eighths into two brackets of three. Verified by engraving 3/5/7-tuplets and reading the brackets.
   - Triple dots supported (two files crashed on them). Dot arithmetic is now the general (2^(n+1)-1)/2^n as an exact integer ratio, so representability is a remainder check; parsers call `Duration.exact?/2` first, turning anything needing rounding into a typed error instead of a raise.

Tests: 67 tests + 3 doctests + 2 properties, 0 failures. Property generators now produce multi-voice measures AND tuplets.
</work_completed>

<work_remaining>
1. **Dataset phase (2026-07-30)**: `docs/data-sources.md` (license-tiered corpus inventory) and `docs/composers.md` (composer who's-who; David Maslanka confirmed as the user's UMSL composer — under copyright, document only) are DONE. Four kern sources added and ingested: inventions 30/30 (44,239 tok), wtc_fugues 46/48 (128,616), haydn_quartets 209/210 (945,328), mozart_quartets 82/82 (428,399) — corpus total now ~2.4M tokens. polish_scores (CC BY, the clean tier's kern giant) ingested 8707/8918 files (97.6%) for 37.2M tokens — the clean-data story is viable TODAY. First error-tail slice DONE: 11/13/15-tuplets supported (divisions 20160 -> 2,882,880; new tuplet tokens APPENDED, vocab 616, chorales shard verified byte-identical) and tokenizer refuses with typed errors instead of crashing ({:unsupported_time,...}, {:key_out_of_range,...}, {:too_many_parts,...}). polish_scores now 8731/8918 (97.9%), 37.48M tokens, zero crashes. Remaining tail: 66 missing_pitch, 55 missing_duration, 37 unsupported_tuplet (17+, mensural), 18 unsupported_duration (128th notes), 6 unsupported_time, 4 too_many_parts, 1 key_out_of_range; plus wtc2f10 pad_rests tuplet-offset crash. 11-tuplet engraving visually verified (Statkowski capriccio m.126). NOTE: renderers are NOT installed on this machine — use `nix shell nixpkgs#librsvg` etc.; verovio via pip venv (needs LD_LIBRARY_PATH to stdenv.cc.cc.lib on NixOS). Key finding: craigsapp/musedata kern encodings are CC BY-NC-SA (not PD); strictly clean stack is PDMX no_license_conflict + OpenScore + Polish Scores + Mutopia PD/CC-BY + BMdataset (PLAN.md §4 corrected). Next data steps: PDMX ingestion (needs MusicXML `<forward>` + interleaved-voice support), OpenScore .mscx conversion path, Polish Scores.
2. **Parser follow-up**: `Kern.Parser.pad_rests/2` (parser.ex:530) only emits binary rests, so a voice entering at a tuplet offset crashes (wtc2f10.krn, "voice offset of 53760 divisions is not notatable" — needs tuplet rest padding; the comment claiming unreachability predates tuplet support). wtc1f20.krn refused on `*x` spine manipulation (known limitation).
2. **Phase 0.5 — first day at the 5090**: export `XLA_TARGET=cuda12` EXPLICITLY (autodetect silently falls back to CPU), uncomment exla in fermata's mix.exs (edifice's dep upgrade is already done), run `edifice/bench/training_throughput.exs` to replace the 30–60k tok/s estimate with a measurement.
3. **Phase 1 training** on bach_chorales (210,974 tokens) and now beethoven_quartets (683,943 tokens, p50 9,688). ~30M params, Edifice subquadratic backbone preferred (no flash attention in XLA → O(seq²) attention memory). LR warmup hand-composed with `Nx.select` (Polaris `linear_decay` ignores `init_value`). Chorales are short (p50 519) so pack ~8 per 4K window instead of padding; quartets are long enough to need real context.
4. **Instrument-conditioned + range-constrained sampling** — registry now has the ranges (`Instruments.in_range?/2`, `Transpose.out_of_range/2`).
5. More duet-shaped data: OpenScore Lieder (MuseScore format, needs conversion), PDMX Zenodo 15571083 (needs MusicXML `<backup>`/`<forward>` multi-voice — backup is DONE now; forward and interleaved voices still missing).
6. Housekeeping: no CLAUDE.md in fermata/ yet (test conventions, append-only vocab warning, renderer notes).
</work_remaining>

<critical_context>
- **APPEND-ONLY TOKEN IDS.** Ids 0..526 are frozen (corpus shards + any trained embedding index them). `Vocab.tokens/0` builds a `phase_0` block, then appends. Instrument tokens sit INSIDE that block, so new instruments go in `Instruments.@added` (appended at the END of the vocab), never in `@phase_0`. Same for `{:voice, n}`, `{:tuplet, a, n}`, 3-dot durations. VERIFY after any vocab change: `mix fermata.corpus bach_chorales` must still report exactly 210,974 tokens.
- Corpus binary format: tokens.bin = u16 little-endian ids; index.etf = `term_to_binary` map with entries `[%{key:, offset: (bytes), tokens:}]` + typed errors. data/ is gitignored, regenerate in seconds.
- REPRESENTATION BET (PLAN.md §1): score-level tokens (spelled pitches, notated durations, measure-interleaved parts), NOT performance MIDI. MusicXML only at the renderer boundary. Fallback if Phase 1 underperforms: NotaGen-style interleaved ABC.
- IR is CONCERT PITCH. Written-pitch transposition is a rendering-time step (`Transpose.to_written/2`), deliberately outside the token stream — `Part.transpose` is presentation metadata the tokenizer ignores.
- Same-voice events must be CONTIGUOUS within a measure; `Measure.voice_groups/1` is the single place that invariant is read. Both parsers produce grouped output; the tokenizer and writer rely on it for exact round-trips.
- NUMERICS: loss math ALWAYS f32; norms excluded from bf16; Axon's dynamic loss scaler applies overflowed grads and only detects inf (not NaN) — smoke-test bf16 on the exact backbone before long runs.
- `Polaris.Updates.apply_updates/2` broken under nx 0.13 (nil default state rejected by jit traversal) — hand-rolled tree `Nx.add` in test/fermata/model_smoke_test.exs is the workaround.
- 5090/EXLA: xla 0.10.0 cuda12 prebuilts have sm_120; `XLA_TARGET` autodetects via nvcc and SILENTLY falls back to CPU. Always `Axon.build(model, compiler: EXLA)`.
- Kern spine order is bass-first; parser reverses so part 0 = top voice.
- Renderers: verovio + lilypond + rsvg-convert installed and working. Verovio multi-page = `score_001.svg` naming.
- Environment (as of 2026-07-30, machine "blewf"): NixOS, fish, Elixir 1.18.4, nx 0.13.0/axon 0.8.1/polaris 0.1.0; exla commented out until the 5090. NEVER pipe test output through head/tail/grep — redirect to a file then read. No emojis. Prefer Elixir over Python for scripting (user called this out). Ask before non-obvious choices.
- Edifice at /home/blewf/git/edifice (main, shared with exphil — see CLAUDE.md "Sharing edifice with exphil"); feature work in the /home/blewf/git/edifice-dev worktree.
- PLAN.md is authoritative for design; §5.1 lists Edifice/Axon/Polaris gaps; §7 phases.
</critical_context>

<current_state>
- Corpus: bach_chorales 370/370 (210,974 tokens); beethoven_quartets **71/71** (683,943 tokens, p50 9,688 / max 18,739). Both training-ready.
- Vocab size 613. Frozen boundary intact (`{:dur, :"64th", 2}` == id 526).
- Tests: 67 + 3 doctests + 2 properties, 0 failures (~3s, CPU).
- Git: pushed to github.com/blasphemetheus/fermata (origin), main.
- Still CPU-only on this machine; 5090 tasks (Phase 0.5) pending.
</current_state>
