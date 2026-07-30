# Symbolic score data sources

Inventory of machine-readable score corpora for training, surveyed
2026-07-30. "Available" here always means symbolic notation (kern,
MusicXML, MEI, ABC, LilyPond, MuseScore `.mscx`/`.mscz`) — scanned PDFs
are not ingestible and OMR is out of scope. Companion document:
`composers.md` maps composers to these sources.

Licensing frame: a public-domain *work* does not make an *encoding*
public domain. Encoders and modern editors claim copyright on their
files (whether encodings of PD music are copyrightable at all is legally
contested, but the strict "trained only on PD/CC0 data" story from
PLAN.md §4 requires taking the claims at face value). US public domain
means published before 1931 (as of 2026, advancing one year each
January); most other countries use life + 70.

## Tier 1 — clean (PD / CC0 / CC BY)

These support the strict story with no caveats beyond per-file filtering.

- **PDMX** — 250K+ MusicXML scores scraped from MuseScore.com with
  license vetting; use the `no_license_conflict` subset (222,856 scores
  where the public license and the embedded file license agree on
  PD/CC0). ~14 GB compressed, Zenodo one-shot download. The flagship
  corpus and, filtered by instrumentation metadata, the only at-scale
  source of band/ensemble arrangements. Caveat: mostly user engravings
  and arrangements, >50% solo, not a curated canon; residual risk of
  user-mislabeled uploads. Zenodo 10.5281/zenodo.15571083 (v9),
  arXiv:2409.10831, github.com/pnlong/PDMX.
- **OpenScore Lieder** — 1,356 19th-century songs (voice + piano),
  `.mscx`, CC0. Brahms 110, Schubert 88, Schumann 72, Fanny Hensel 35,
  Clara Schumann 17. github.com/OpenScore/Lieder.
- **OpenScore String Quartets** — 122 quartets, `.mscx`, CC0. Haydn 28,
  Mozart 15, Mendelssohn 4, Brahms 3, plus Debussy and Ravel quartets.
  The best CC0 four-part contrapuntal data anywhere.
  github.com/OpenScore/StringQuartets.
- **Polish Scores** — 8,918 kern files, 13M+ notes, CC BY 4.0. Polish
  musical heritage 1600–1900, 700+ composers, sacred vocal and
  instrumental. One of the largest clean kern collections and broadly
  overlooked. github.com/pl-wnifc/humdrum-polish-scores.
- **Mutopia (PD/CC BY slice)** — 2,124 pieces total in native LilyPond,
  per-piece licenses (PD dedication, CC BY, CC BY-SA); filter by the
  license field. Bach 417, Mozart 96, Beethoven 77, Handel 58. Dormant
  since 2019 but clonable. mutopiaproject.org,
  github.com/MutopiaProject/MutopiaProject.
- **BMdataset / LilyBERT** — 393 Baroque scores / 2,646 movements /
  ~90M tokens, expert-transcribed LilyPond with rich metadata, CC BY
  4.0. The only curated LilyPond-native corpus. arXiv:2604.10628,
  huggingface.co/csc-unipd.
- **ChoraleBricks** — 10 chorales for brass ensemble, per-voice
  MusicXML + MEI 5.0, CC BY 4.0. Tiny, but genuinely wind-scored.
  Zenodo 10.5281/zenodo.15081741, TISMIR 10.5334/tismir.252.

## Tier 1.5 — share-alike (CC BY-SA)

Trainable if share-alike obligations are acceptable; outside a strict
"PD/CC0/CC BY only" line.

- **Josquin Research Project** — ~1,400 kern files of Renaissance
  polyphony ca. 1420–1520 (Josquin 475, La Rue 172, Martini 122, Gaspar
  110, Ockeghem 98, ...), complete-works quality, mostly without lyrics.
  Meta-repo license CC BY-SA 4.0, but individual scores may carry
  work-specific notices and some submodules lack license files — check
  per repo. github.com/josquin-research-project/jrp-scores.
- **TAVERN** — 27 Mozart/Beethoven theme-and-variation sets (281
  variations) in kern with dual harmonic annotations, CC BY-SA 4.0.
  github.com/jcdevaney/TAVERN.

## Tier 2 — quarantine (NC licenses, murky terms, per-file triage)

Usable for a personal research project; excluded from any
commercial-clean claim.

- **craigsapp / musedata / humdrum-tools kern repos** — the classical
  kern canon: `bach-370-chorales` (370), `beethoven-string-quartets`
  (71), `beethoven-piano-sonatas` (103), `mozart-piano-sonatas` (69),
  `humdrum-mozart-quartets` (82), `humdrum-haydn-quartets` (210),
  `haydn-piano-sonatas` (25), `humdrum-haydn-symphonies` (99–104 only,
  24), `bach-wtc` (96), `bach-wtc-fugues` (part-split), `inventions`
  (30), `humdrum-bach-brandenburg` (21), `humdrum-corelli` (250),
  `chopin-mazurkas` (52), `chopin-preludes` (24),
  `chopin-humdrum-nifc` / `humdrum-chopin-first-editions` (512),
  `scarlatti-keyboard-sonatas` (65), `scriabin`, `joplin` (47),
  `vivaldi` repos, `art-of-the-fugue` (20), `bach-musical-offering`.
  **License: CC BY-NC-SA 4.0** (verified on bach-370-chorales and
  mozart-piano-sonatas; assume family-wide, spot-check others —
  scarlatti shows custom text). This corrects PLAN.md §4, which listed
  KernScores as plain PD: the works are PD, the encodings claim NC.
  Note kern.humdrum.org and kern.ccarh.org were both unreachable at
  survey time — the GitHub repos are the ingestion path. The
  `humdrum-tools/humdrum-data` meta-repo aggregates 26 sources / 26,490
  files with per-directory license info and is the sane bulk plumbing.
- **DCML corpora** — annotated Beethoven quartets (ABC), all Mozart
  sonatas, complete Debussy piano, Chopin mazurkas, Corelli, Grieg
  Lyric Pieces, and ~20 more; `.mscx` + expert harmony TSVs. CC
  BY-NC-SA 4.0. The annotations are unique; the NC keeps it here.
  github.com/DCMLab/dcml_corpora.
- **CPDL / ChoralWiki** — ~51,400 choral works, but PDF-universal with
  source files (increasingly `.mxl`) on only an unquantified minority;
  per-file licenses (CPDL license, CC, personal); no bulk download.
  High triage cost for an unknown yield.
- **Essen Folksong Collection** — 8,379 kern folk melodies; formally
  "distributed by license only" (Schaffrath estate) despite ubiquitous
  MIR use.
- **Nottingham Music Database** — ~1,200 folk tunes in ABC, no formal
  license.
- **Meertens Tune Collections** — Dutch folk songs in kern/LilyPond;
  license varies per release (older raw data CC BY-NC-SA); verify
  before use.
- **1520s Project** — 600+ scores of 1510–1540 polyphony, multiple
  formats, CC BY-NC 4.0. github.com/benory/1520s-project-scores.
- **IrishMAN and similar Hugging Face ABC sets** — 216K tunes relabeled
  MIT, but sourced from thesession.org (see below) and
  abcnotation.com — license laundering; inherits the poison.
- **Victoria complete works (victoria.uma.es)** — 321 pieces with
  LilyPond source (1,359 across the site with other Spanish
  polyphonists); free but no standard license stated — verify terms.

## Tier 3 — not trainable

- **thesession.org data dumps** — the ODbL license now carries an
  explicit supplemental clause prohibiting LLM training. Decisive, and
  it contaminates derivatives (IrishMAN, most modern ABC folk sets).
- **MuseScore.com direct** — per-upload licenses default to all-rights-
  reserved, widespread mislabeling, ToS forbids scraping. PDMX is
  exactly the vetted extraction of this site; use it instead.
- **IMSLP** — 736K+ scores but overwhelmingly scans; no enumerable
  symbolic subset. Useful as a PD-status reference and edition source,
  not as data.
- **SOD / SymphonyNet dataset** — orchestral MIDI/MusicXML scraped
  largely from commercial subscription sites, no stated licenses.
  PLAN.md §4 already quarantines these; they stay out.
- **WikiMusicText** — 1,010 ABC lead sheets from the defunct Wikifonia,
  CC BY-NC and never rights-clean upstream.
- **BandMusic PD Library (bandmusicpdf.org)** — 4,000+ genuinely PD
  American band titles ca. 1870s–1924, but scanned parts only. Valuable
  as a repertoire index of what is safely PD, and as a source for human
  retranscription if that door ever opens.
- **NotaGen / MuPT pretraining corpora** — never released (weights
  only). No large clean notation corpus has appeared since PDMX.

## Systemic gaps

- **Orchestral music is the desert.** Open symbolic data covers
  keyboard, quartets, chorales and songs superbly; symphonies exist
  only as the Brandenburgs, Haydn 99–104, and MuseData stage2. Nothing
  open for Brahms, Tchaikovsky, Dvorak, Mahler or Sibelius orchestral
  works beyond user-quality MuseScore uploads.
- **No curated symbolic wind-band corpus exists anywhere.** The
  realistic path is PDMX filtered by instrumentation for CC0/PD
  engravings of PD band repertoire (Sousa, Holst suites, pre-1931
  Gershwin), plus ChoraleBricks.
- **Folk ABC is legally wrecked** by the thesession clause and
  unlicensed legacy collections; the clean folk sources are Polish
  Scores adjacent repertoire and Mutopia's traditional slice.

## Practical consequences for fermata

1. Both currently ingested sources (bach_chorales,
   beethoven_quartets) are CC BY-NC-SA encodings — fine for this
   learning project, but the strict PD/CC0 story requires either
   retiring them from any released model's training set or accepting
   "NC-encumbered encodings of PD works" as a documented asterisk.
2. The commercial-clean maximal stack is: PDMX no_license_conflict +
   OpenScore (both) + Polish Scores + Mutopia PD/CC-BY + BMdataset +
   ChoraleBricks — roughly 235K scores.
3. Duet-shaped and Phase 1/2 priorities among parser-ready kern:
   `inventions` (2–3 real parts), `bach-wtc-fugues` (parts pre-split to
   staves), `humdrum-haydn-quartets`, `humdrum-mozart-quartets`,
   `humdrum-corelli` (trio sonatas), `humdrum-bach-brandenburg`.
   OpenScore needs a `.mscx` conversion step (MuseScore headless needs
   Xvfb — prefer converting once on another machine or via mscx→
   MusicXML tooling) before its CC0 data is reachable.
