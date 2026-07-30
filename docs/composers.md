# Composer intake roster — the who's who

Which composers we want the model to learn from, what data exists, and
whether we may train on it. Surveyed 2026-07-30; companion document
`data-sources.md` describes every corpus cited here. US public domain =
published before 1931 (as of 2026); life + 70 elsewhere; and always
remember the trap: a PD *work* in a modern *edition* (Boosey revisions,
Ives Society critical editions, Barnhouse reprints) carries editorial
copyright — only original-era plates or license-verified encodings are
clean.

Verdicts:

- **trainable now** — clean symbolic data exists today
- **trainable, NC-encumbered** — symbolic data exists but under
  CC BY-NC-SA encodings (fine for this project, outside the strict story)
- **PD, no symbolic data** — legally free, nothing machine-readable yet;
  candidates for targeted transcription
- **document only** — under copyright; listed for the wishlist, not the
  training set

## Renaissance and early music

- **Josquin des Prez** (c.1450–1521) and the JRP circle (Ockeghem, La
  Rue, Gaspar, Obrecht, Du Fay, Busnoys, Martini) — the polyphonic
  foundation; ~1,400 complete-works-quality kern files in the Josquin
  Research Project (CC BY-SA). **Trainable now** (share-alike caveat).
- **Palestrina** (c.1525–1594) — the counterpoint textbook made flesh;
  ~101 masses / 713 movements in kern via the music21 corpus.
  **Trainable now** (verify the sub-corpus license).
- **Victoria** (1548–1611) — complete works with LilyPond source at
  victoria.uma.es (321 pieces). **Trainable pending license check.**
- **Lassus** (1532–1594) — 50 psalm settings in kern.
  **Trainable, NC-unclear** — small but clean repertoire fit.
- **Monteverdi** (1567–1643) — madrigal books 3–5 in kern (music21),
  DCML madrigals (NC). **Trainable now** for the madrigals; operas have
  no open edition.
- **Byrd** (c.1540–1623) and **Dowland** (1563–1626) — PD forever, but
  staff-notation symbolic data is piecemeal (CPDL per-work; lute
  repertoire is in tablature). **PD, little symbolic data.**

## Baroque

- **J.S. Bach** (1685–1750) — the best-covered composer in existence
  and our Phase 1 backbone: 370 + 185 chorales, WTC complete (96), the
  part-split WTC fugues, inventions (30), Brandenburgs (21 movements),
  Art of Fugue, Musical Offering — all kern, all CC BY-NC-SA; cello
  suites and 417 pieces on Mutopia (per-piece PD/CC). **Trainable,
  NC-encumbered** (Mutopia slice clean).
- **Corelli** (1653–1713) — Opp. 1–6 complete, 250 kern files; trio
  sonatas are gloriously duet-adjacent. **Trainable, NC-encumbered.**
- **Vivaldi** (1678–1741) — ~46 kern files plus op. 3/op. 6 repos.
  **Trainable, NC-encumbered.**
- **Handel** (1685–1759) — shockingly thin: 58 Mutopia pieces, MuseData
  legacy only. **PD, surprisingly little symbolic data.**
- **Telemann** (1681–1767) — near-nothing symbolic. **PD, no symbolic
  data** — a genuine gap given his chamber output would suit duets.
- **D. Scarlatti** (1685–1757) — 65 of 555 sonatas in kern.
  **Trainable, NC-encumbered.**

## Classical

- **Haydn** (1732–1809) — 210 quartet movements in kern, 28 quartets in
  OpenScore (CC0), piano sonatas (25), symphonies 99–104 only.
  **Trainable now** (OpenScore) plus NC kern depth.
- **Mozart** (1756–1791) — 82 quartet movements + 69 sonata movements
  in kern, 15 OpenScore quartets, 96 Mutopia pieces, TAVERN variations.
  **Trainable now** plus NC kern depth. Symphonies: gap.
- **Beethoven** (1770–1827) — all 32 sonatas (103 files) and all 16
  quartets (71 files, already ingested) in kern; DCML harmonic
  annotations (NC). **Trainable, NC-encumbered.** Symphonies: no open
  critical edition — the starkest Classical gap.

## Romantic

- **Schubert** (1797–1828) — 88 OpenScore songs (CC0), Winterreise
  annotated (NC), Mutopia 55. **Trainable now.**
- **Schumann** (1810–1856) and **Clara Schumann** (1819–1896) — 72 + 17
  OpenScore songs, DCML Kinderszenen/Liederkreis (NC). **Trainable
  now.**
- **Mendelssohn** (1809–1847) and **Fanny Hensel** (1805–1847) — 12 +
  35 OpenScore songs, 4 + 1 OpenScore quartets; OpenScore is the best
  Hensel source anywhere. **Trainable now.**
- **Chopin** (1810–1849) — the best-covered Romantic in kern: NIFC
  first editions complete (512 files, CC BY-NC-SA), mazurkas, preludes,
  47 Mutopia pieces. **Trainable, NC-encumbered** (Mutopia slice clean).
- **Brahms** (1833–1897) — zero kern, but 110 OpenScore songs (his
  largest single-composer holding) + 3 quartets. **Trainable now** for
  songs/quartets; orchestral gap.
- **Liszt, Dvorak, Tchaikovsky, Grieg, Faure** — thin everywhere:
  DCML piano sets (NC), a few OpenScore quartets, single-digit Mutopia
  counts. **PD, little symbolic data** outside those slices; orchestral
  works absent.

## Late and post-Romantic

- **Debussy** (1862–1918) — complete solo piano in DCML (NC), 16
  melodies + 1 quartet in OpenScore (CC0). **Trainable now** (CC0
  slice) / NC for the piano corpus.
- **Ravel** (1875–1937) — PD in life+70 countries since 2008; US PD for
  pre-1931 publications (nearly all major works; Bolero cleared in
  2025). DCML piano (NC), OpenScore quartet (CC0). **Trainable now**
  (thinly).
- **Satie** (1866–1925), **Scriabin** (1872–1915) — fully PD; Mutopia
  16 / craigsapp scriabin kern respectively. **Trainable** (Satie now,
  Scriabin NC-encumbered).
- **Mahler** (1860–1911) — fully PD, and effectively zero open symbolic
  data beyond Kindertotenlieder annotations. **PD, no symbolic data** —
  the starkest famous-composer gap.
- **Rachmaninoff** (1873–1943) — life+70 PD since 2014; US per-work
  (pre-1931 works PD; Paganini Rhapsody 2030, Symphonic Dances 2037).
  DCML piano (NC). **Mostly PD, thin data.**
- **Sibelius** (1865–1957) — under copyright in life+70 countries until
  2028; no symbolic corpora anyway. **Document only until 2028.**

## Wind ensemble and band

The reason this section exists: no curated symbolic band corpus exists
anywhere. For PD entries, "trainable" means mining PDMX/MuseScore
CC0-licensed engravings; BandMusic PD Library (4,000+ titles,
1870s–1924) proves what repertoire is safely PD but is scans-only.

- **John Philip Sousa** (1854–1932) — the march form itself; virtually
  everything published pre-1931. US and life+70 PD. CC0/PD full-band
  engravings exist on MuseScore/PDMX. **Trainable now**
  (license-filtered).
- **Gustav Holst** (1874–1934) — First Suite in E-flat (pub. 1921) and
  Second Suite in F (pub. 1922), the founding documents of band
  literature; both US PD, PD everywhere since 2005. Avoid the revised
  1984 Boosey editions (editorial copyright). **Trainable now**
  (license-filtered engravings).
- **Ralph Vaughan Williams** (1872–1958) — English Folk Song Suite
  (1923), Toccata Marziale (1924): US PD now, EU/UK PD 2029-01-01.
  **Trainable now under US law** (flag the EU date).
- **Percy Grainger** (1882–1961) — Lincolnshire Posy (1937) has a
  strong US-PD-by-non-renewal case (no renewal found in the Catalog of
  Copyright Entries; Musopen distributes it); pre-1931 works (Irish
  Tune, Shepherd's Hey, Molly on the Shore) are US PD outright.
  **Trainable per-work** after verifying renewal status.
- **Charles Ives** (1874–1954) — PD worldwide since 2025-01-01 (and
  much US PD earlier via non-renewal). Use first editions, not Ives
  Society critical editions. Modest symbolic data. **PD, little
  symbolic data — prime transcription target.**
- **George Gershwin** (1898–1937) — Rhapsody in Blue (US PD 2020) and
  all pre-1931 works are fair game; post-1930 (Porgy and Bess) is not.
  Abundant MuseScore transcriptions to license-filter. **Trainable now
  (pre-1931 works).**
- **Karl L. King** (1891–1971) and **Henry Fillmore** (1881–1956) —
  circus-march royalty; famous marches pub. pre-1931 = US PD (Barnhouse
  modern editions excluded). **PD, essentially no symbolic data.**
- **Nikolai Myaskovsky** (1881–1950) — Symphony No. 19 for band (1939):
  life+70 PD since 2021 but GATT-restored in the US until ~2037; his
  pre-1931 works are US PD with no symbolic data. **Document only**
  (Sym. 19); **PD, no data** (early works).
- **Boris Kozhevnikov** (1906–1985) — Symphony No. 3 "Slavyanskaya";
  GATT-restored, and the American performing edition is Bourgeois 1995
  (Wingert-Jones). **Document only.**
- **Aaron Copland** (1900–1990) — the American sound; everything of
  consequence copyrighted (Boosey & Hawkes / Copland Fund) until
  2037+ per work, life+70 to 2061. **Document only.**
- **David Maslanka** (1943–2017) — the confirmed UMSL composer: A
  Child's Garden of Dreams, Symphony No. 4, Give Us This Day; central
  modern wind-ensemble voice. Self-published, estate-run Maslanka
  Press; life+70 to 2088. **Document only** — admire, perform, do not
  ingest.
- **Alfred Reed** (1921–2005) — Russian Christmas Music, Armenian
  Dances; among the most-performed band composers ever. Copyrighted to
  2040+. **Document only.**
- **Persichetti** (1915–1987), **Morton Gould** (1913–1996), **Barber**
  (1910–1981), **Bernstein** (1918–1990) — the mid-century American
  concert canon; all controlled by major publishers (Presser, Schirmer,
  Boosey). **Document only.**
- **Ticheli** (b. 1958), **Mackey** (b. 1973), **Whitacre** (b. 1970) —
  living; Mackey and Whitacre self-publish and are performance-friendly
  but grant no corpus rights. **Document only.**

## Ragtime and jazz

- **Scott Joplin** (1868–1917) — fully PD, and 47 rags exist in kern
  (craigsapp/joplin, CC BY-NC-SA). The one "jazz-adjacent" composer who
  is both PD and encoded. **Trainable, NC-encumbered.**
- **Jazz standards generally** — the Great American Songbook is largely
  post-1930 and aggressively administered; lead-sheet corpora (iRb,
  Weimar Jazz Database, WikiMusicText) are research-only or
  rights-murky. Pre-1931 early jazz and Tin Pan Alley compositions are
  US PD, but symbolic data is scarce. **Document only** as a category,
  with pre-1931 exceptions handled per-work.

## Where this leaves the training set

Densest legal, high-quality stacks by phase: Bach chorales + inventions
+ WTC fugues (NC-encumbered) and OpenScore Lieder (CC0) for Phase 1;
OpenScore Quartets + Haydn/Mozart/Beethoven quartet kern + Corelli for
Phase 2; PDMX throughout. The wishlist beyond legality — Copland,
Maslanka, Reed — stays a wishlist until 2037+, and the model's
"American band" flavor will have to come from Sousa, Holst, Grainger,
Ives and Gershwin, which is honestly a respectable band folder.
