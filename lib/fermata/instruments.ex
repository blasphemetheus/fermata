defmodule Fermata.Instruments do
  @moduledoc """
  The instrument registry: identity, family, clef, **transposition**, and
  practical range.

  ## What "in B♭" means here

  A transposing instrument's player reads one pitch and a different pitch
  comes out. The registry stores that as one directed interval, always in
  the same direction: **written → sounding**. A B♭ clarinet reading C
  sounds B♭, a major second lower, so its transposition is a major second
  *down*. Everything else — the written key signature, the MusicXML
  `<transpose>` element, whether a note fits the range — is derived from
  that single fact by `Fermata.Transpose`.

  The inverse direction is the one arrangers think in ("what do I write so
  it sounds right?") and it is just `Interval.negate/1`.

  ## Token id stability

  This roster is the source of the tokenizer's instrument vocabulary, so
  **ids depend on list position**. The Phase 0 block (`@phase_0`) is
  frozen: never reorder or remove. Instruments discovered later go in
  `@added`, which `Fermata.Vocab` appends *after* the entire Phase 0
  token block precisely so that adding an instrument cannot shift the id
  of a pitch or duration token in corpora already on disk.

  ## Browsing

      Fermata.Instruments.info(:clarinet_bb)
      Fermata.Instruments.transposing()
      Fermata.Instruments.by_family(:woodwind)
      Fermata.Instruments.find("Bb Clarinet")

  or from a shell, formatted as a table:

      mix fermata.instruments
      mix fermata.instruments --family woodwind
      mix fermata.instruments --transposing
  """

  alias Fermata.{Interval, Pitch}

  # Interval helpers, written → sounding.
  defp down(interval), do: Interval.negate(interval)
  defp up(interval), do: interval

  # ── The roster ──────────────────────────────────────────────────────
  #
  # Fields: id, name, family, clef, transposition (nil = concert pitch),
  # sounding range as {low_midi, high_midi} (nil = not catalogued),
  # aliases (matched case/punctuation-insensitively; Humdrum *I codes
  # included, since kern corpora identify parts with those).

  @phase_0 [
    %{id: :soprano, name: "Soprano", family: :voice, clef: :treble, range: {60, 81},
      aliases: ["soprn", "s"]},
    %{id: :alto, name: "Alto", family: :voice, clef: :treble, range: {55, 76},
      aliases: ["a"]},
    %{id: :tenor, name: "Tenor", family: :voice, clef: :treble_8vb, range: {48, 69},
      aliases: ["t"]},
    %{id: :bass, name: "Bass", family: :voice, clef: :bass, range: {40, 62},
      aliases: ["b"]},
    %{id: :violin, name: "Violin", family: :strings, clef: :treble, range: {55, 103},
      aliases: ["violn", "violino", "vln", "vn", "violin 1", "violin 2", "violino 1", "violino 2"]},
    %{id: :viola, name: "Viola", family: :strings, clef: :alto, range: {48, 88},
      aliases: ["vla", "va"]},
    %{id: :cello, name: "Violoncello", family: :strings, clef: :bass, range: {36, 84},
      aliases: ["cello", "violoncello", "vlc", "vc"]},
    %{id: :contrabass, name: "Contrabass", family: :strings, clef: :bass, range: {28, 67},
      transposition: :octave_down,
      aliases: ["cbass", "double bass", "doublebass", "bass viol", "cb", "db"]},
    %{id: :flute, name: "Flute", family: :woodwind, clef: :treble, range: {60, 98},
      aliases: ["flt", "flauto", "fl"]},
    %{id: :piccolo, name: "Piccolo", family: :woodwind, clef: :treble, range: {74, 108},
      transposition: :octave_up,
      aliases: ["picco", "flauto piccolo", "picc"]},
    %{id: :oboe, name: "Oboe", family: :woodwind, clef: :treble, range: {58, 93},
      aliases: ["ob"]},
    %{id: :english_horn, name: "English Horn", family: :woodwind, clef: :treble, range: {45, 81},
      transposition: :perfect_fifth_down,
      aliases: ["cor anglais", "corno inglese", "englishhorn", "eh"]},
    # The unqualified names are the common instruments: a "clarinet" with
    # no key given is a B♭ clarinet, a "horn" is in F, a "trumpet" in B♭.
    %{id: :clarinet, name: "Clarinet", family: :woodwind, clef: :treble, range: {50, 94},
      transposition: :major_second_down,
      aliases: ["clars", "clarinetto", "cl", "bb clarinet", "clarinet in bb",
                "clarinet in b flat", "soprano clarinet"]},
    %{id: :bass_clarinet, name: "Bass Clarinet", family: :woodwind, clef: :treble, range: {34, 75},
      transposition: :major_ninth_down,
      aliases: ["clarinetto basso", "bcl", "bass clarinet in bb"]},
    %{id: :bassoon, name: "Bassoon", family: :woodwind, clef: :bass, range: {34, 75},
      aliases: ["fagot", "fagotto", "bsn", "bn"]},
    %{id: :contrabassoon, name: "Contrabassoon", family: :woodwind, clef: :bass, range: {22, 63},
      transposition: :octave_down,
      aliases: ["contrafagotto", "double bassoon", "cbsn"]},
    %{id: :horn, name: "Horn", family: :brass, clef: :treble, range: {35, 77},
      transposition: :perfect_fifth_down,
      aliases: ["cor", "corno", "french horn", "hn", "horn in f", "f horn"]},
    %{id: :trumpet, name: "Trumpet", family: :brass, clef: :treble, range: {52, 84},
      transposition: :major_second_down,
      aliases: ["tromp", "tromba", "tpt", "tp", "bb trumpet", "trumpet in bb"]},
    %{id: :trombone, name: "Trombone", family: :brass, clef: :bass, range: {40, 77},
      aliases: ["tromb", "trombono", "tbn", "tb"]},
    %{id: :bass_trombone, name: "Bass Trombone", family: :brass, clef: :bass, range: {34, 70},
      aliases: ["btbn"]},
    %{id: :tuba, name: "Tuba", family: :brass, clef: :bass, range: {26, 65},
      aliases: ["tba"]},
    %{id: :timpani, name: "Timpani", family: :percussion, clef: :bass, range: {36, 60},
      aliases: ["timpa", "timp", "kettledrums"]},
    %{id: :harp, name: "Harp", family: :keyboard, clef: :treble, range: {23, 103},
      aliases: ["arpa", "hp"]},
    %{id: :piano, name: "Piano", family: :keyboard, clef: :treble, range: {21, 108},
      aliases: ["pianoforte", "pno", "pf"]},
    %{id: :organ, name: "Organ", family: :keyboard, clef: :treble, range: {24, 96},
      aliases: ["orgue", "org"]},
    %{id: :harpsichord, name: "Harpsichord", family: :keyboard, clef: :treble, range: {29, 89},
      aliases: ["cemba", "cembalo", "clavecin", "hpschd"]},
    %{id: :guitar, name: "Guitar", family: :strings, clef: :treble_8vb, range: {40, 83},
      transposition: :octave_down,
      aliases: ["guitr", "chitarra", "gtr"]},
    %{id: :recorder, name: "Recorder", family: :woodwind, clef: :treble, range: {72, 105},
      aliases: ["recor", "blockflote", "rec"]},
    %{id: :voice, name: "Voice", family: :voice, clef: :treble, range: nil,
      aliases: ["vox", "vocal"]},
    %{id: :mezzo_soprano, name: "Mezzo-soprano", family: :voice, clef: :treble, range: {57, 79},
      aliases: ["mezzo", "ms"]},
    %{id: :baritone, name: "Baritone", family: :voice, clef: :bass, range: {45, 65},
      aliases: ["barit", "bar"]},
    %{id: :percussion, name: "Percussion", family: :percussion, clef: :treble, range: nil,
      aliases: ["perc", "drums"]}
  ]

  # Appended after Phase 0 — see "Token id stability" above.
  @added [
    # Clarinet family, by key
    %{id: :clarinet_c, name: "Clarinet in C", family: :woodwind, clef: :treble, range: {52, 96},
      aliases: ["c clarinet"]},
    %{id: :clarinet_a, name: "Clarinet in A", family: :woodwind, clef: :treble, range: {49, 93},
      transposition: :minor_third_down,
      aliases: ["a clarinet", "clarinet in a"]},
    %{id: :clarinet_d, name: "Clarinet in D", family: :woodwind, clef: :treble, range: {54, 98},
      transposition: :major_second_up,
      aliases: ["d clarinet"]},
    %{id: :clarinet_eb, name: "Clarinet in E♭", family: :woodwind, clef: :treble, range: {55, 99},
      transposition: :minor_third_up,
      aliases: ["eb clarinet", "clarinet in eb", "sopranino clarinet"]},
    %{id: :clarinet_ab, name: "Clarinet in A♭", family: :woodwind, clef: :treble, range: {60, 104},
      transposition: :minor_sixth_up,
      aliases: ["ab clarinet", "clarinet in ab", "piccolo clarinet"]},
    %{id: :contra_alto_clarinet, name: "Contra-alto Clarinet in E♭", family: :woodwind,
      clef: :treble, range: {27, 68}, transposition: :major_thirteenth_down,
      aliases: ["eb contra alto clarinet", "contralto clarinet"]},
    %{id: :contrabass_clarinet, name: "Contrabass Clarinet in B♭", family: :woodwind,
      clef: :treble, range: {22, 63}, transposition: :two_octaves_major_second_down,
      aliases: ["bb contrabass clarinet"]},
    %{id: :basset_horn, name: "Basset Horn in F", family: :woodwind, clef: :treble,
      range: {41, 77}, transposition: :perfect_fifth_down,
      aliases: ["corno di bassetto"]},

    # Saxophones
    %{id: :sopranino_sax, name: "Sopranino Saxophone in E♭", family: :woodwind, clef: :treble,
      range: {61, 92}, transposition: :minor_third_up,
      aliases: ["sopranino saxophone", "eb sopranino sax"]},
    %{id: :soprano_sax, name: "Soprano Saxophone in B♭", family: :woodwind, clef: :treble,
      range: {56, 88}, transposition: :major_second_down,
      aliases: ["soprano saxophone", "bb soprano sax", "sop sax"]},
    %{id: :alto_sax, name: "Alto Saxophone in E♭", family: :woodwind, clef: :treble,
      range: {49, 80}, transposition: :major_sixth_down,
      aliases: ["alto saxophone", "eb alto sax", "alto sax", "asax"]},
    %{id: :tenor_sax, name: "Tenor Saxophone in B♭", family: :woodwind, clef: :treble,
      range: {44, 76}, transposition: :major_ninth_down,
      aliases: ["tenor saxophone", "bb tenor sax", "tenor sax", "tsax"]},
    %{id: :baritone_sax, name: "Baritone Saxophone in E♭", family: :woodwind, clef: :treble,
      range: {36, 68}, transposition: :major_thirteenth_down,
      aliases: ["baritone saxophone", "eb baritone sax", "bari sax"]},
    %{id: :bass_sax, name: "Bass Saxophone in B♭", family: :woodwind, clef: :treble,
      range: {32, 63}, transposition: :two_octaves_major_second_down,
      aliases: ["bass saxophone", "bb bass sax"]},

    # Other transposing winds
    %{id: :alto_flute, name: "Alto Flute in G", family: :woodwind, clef: :treble,
      range: {55, 93}, transposition: :perfect_fourth_down,
      aliases: ["g alto flute", "flauto contralto"]},
    %{id: :bass_flute, name: "Bass Flute", family: :woodwind, clef: :treble,
      range: {48, 86}, transposition: :octave_down,
      aliases: ["flauto basso"]},
    %{id: :oboe_damore, name: "Oboe d'amore in A", family: :woodwind, clef: :treble,
      range: {55, 89}, transposition: :minor_third_down,
      aliases: ["oboe damore", "oboe d amore"]},

    # Brass, by key
    %{id: :horn_eb, name: "Horn in E♭", family: :brass, clef: :treble, range: {34, 76},
      transposition: :major_sixth_down,
      aliases: ["eb horn"]},
    %{id: :trumpet_c, name: "Trumpet in C", family: :brass, clef: :treble, range: {54, 86},
      aliases: ["c trumpet"]},
    %{id: :trumpet_d, name: "Trumpet in D", family: :brass, clef: :treble, range: {56, 88},
      transposition: :major_second_up,
      aliases: ["d trumpet"]},
    %{id: :trumpet_eb, name: "Trumpet in E♭", family: :brass, clef: :treble, range: {57, 89},
      transposition: :minor_third_up,
      aliases: ["eb trumpet"]},
    %{id: :cornet, name: "Cornet in B♭", family: :brass, clef: :treble, range: {52, 84},
      transposition: :major_second_down,
      aliases: ["bb cornet", "cornetto"]},
    %{id: :flugelhorn, name: "Flugelhorn in B♭", family: :brass, clef: :treble, range: {50, 82},
      transposition: :major_second_down,
      aliases: ["bb flugelhorn", "flugel horn"]},
    %{id: :euphonium, name: "Euphonium", family: :brass, clef: :bass, range: {34, 70},
      aliases: ["euph"]},

    # ── Rest of the flute family ──
    # The band/orchestra instrument is the concert flute in C above — no
    # transposition, and not called a "soprano flute". These are the
    # genuinely uncommon members.
    %{id: :treble_flute, name: "Treble Flute in G", family: :woodwind, clef: :treble,
      range: nil, transposition: :perfect_fifth_up,
      aliases: ["g treble flute"]},
    %{id: :soprano_flute, name: "Soprano Flute in E♭", family: :woodwind, clef: :treble,
      range: nil, transposition: :minor_third_up,
      aliases: ["eb soprano flute"]},
    %{id: :contra_alto_flute, name: "Contra-alto Flute in G", family: :woodwind, clef: :bass,
      range: nil, transposition: :octave_perfect_fourth_down,
      aliases: ["g contra alto flute"]},
    %{id: :contrabass_flute, name: "Contrabass Flute", family: :woodwind, clef: :bass,
      range: nil, transposition: :two_octaves_down,
      aliases: ["cbass flute"]},

    # ── Plucked / electric strings ──
    # Violin, viola and cello are concert pitch and already in the roster;
    # the strings that transpose all do it by the octave.
    %{id: :bass_guitar, name: "Bass Guitar", family: :strings, clef: :bass, range: {28, 67},
      transposition: :octave_down,
      aliases: ["electric bass", "bass gtr", "ebass"]},
    %{id: :electric_guitar, name: "Electric Guitar", family: :strings, clef: :treble_8vb,
      range: {40, 88}, transposition: :octave_down,
      aliases: ["egtr", "elec guitar"]},
    %{id: :mandolin, name: "Mandolin", family: :strings, clef: :treble, range: {55, 96},
      aliases: ["mand", "mandolino"]},
    %{id: :banjo, name: "Banjo", family: :strings, clef: :treble, range: nil,
      aliases: ["bjo"]},

    # ── Remaining brass ──
    %{id: :trumpet_a, name: "Trumpet in A", family: :brass, clef: :treble, range: nil,
      transposition: :minor_third_down,
      aliases: ["a trumpet"]},
    %{id: :trumpet_f, name: "Trumpet in F", family: :brass, clef: :treble, range: nil,
      transposition: :perfect_fourth_up,
      aliases: ["f trumpet"]},
    %{id: :piccolo_trumpet_bb, name: "Piccolo Trumpet in B♭", family: :brass, clef: :treble,
      range: nil, transposition: :minor_seventh_up,
      aliases: ["bb piccolo trumpet"]},
    %{id: :piccolo_trumpet_a, name: "Piccolo Trumpet in A", family: :brass, clef: :treble,
      range: nil, transposition: :major_sixth_up,
      aliases: ["a piccolo trumpet"]},
    %{id: :bass_trumpet_bb, name: "Bass Trumpet in B♭", family: :brass, clef: :treble,
      range: nil, transposition: :major_ninth_down,
      aliases: ["bb bass trumpet"]},
    %{id: :bass_trumpet_c, name: "Bass Trumpet in C", family: :brass, clef: :treble,
      range: nil, transposition: :octave_down,
      aliases: ["c bass trumpet"]},
    %{id: :cornet_eb, name: "Cornet in E♭", family: :brass, clef: :treble, range: nil,
      transposition: :minor_third_up,
      aliases: ["eb cornet", "soprano cornet"]},
    %{id: :alto_horn, name: "Alto Horn in E♭", family: :brass, clef: :treble, range: nil,
      transposition: :major_sixth_down,
      aliases: ["tenor horn", "eb alto horn", "eb tenor horn"]},
    %{id: :mellophone, name: "Mellophone in F", family: :brass, clef: :treble, range: nil,
      transposition: :perfect_fifth_down,
      aliases: ["f mellophone"]},
    %{id: :baritone_horn, name: "Baritone Horn in B♭", family: :brass, clef: :treble,
      range: {34, 70}, transposition: :major_ninth_down,
      aliases: ["bb baritone horn", "baritone treble"]},
    %{id: :euphonium_bb, name: "Euphonium in B♭", family: :brass, clef: :treble,
      range: {34, 70}, transposition: :major_ninth_down,
      aliases: ["bb euphonium", "euphonium treble"]},
    %{id: :wagner_tuba_bb, name: "Wagner Tuba in B♭", family: :brass, clef: :treble,
      range: nil, transposition: :major_second_down,
      aliases: ["bb wagner tuba"]},
    %{id: :wagner_tuba_f, name: "Wagner Tuba in F", family: :brass, clef: :treble,
      range: nil, transposition: :perfect_fifth_down,
      aliases: ["f wagner tuba"]},
    %{id: :alto_trombone, name: "Alto Trombone", family: :brass, clef: :alto, range: nil,
      aliases: ["atbn"]},
    %{id: :contrabass_trombone, name: "Contrabass Trombone", family: :brass, clef: :bass,
      range: nil, aliases: ["cbtbn"]},
    %{id: :cimbasso, name: "Cimbasso", family: :brass, clef: :bass, range: nil, aliases: []},
    %{id: :sousaphone, name: "Sousaphone", family: :brass, clef: :bass, range: {26, 65},
      aliases: ["sousa"]},

    # Natural-horn crooks. Older scores name the crook rather than
    # transposing to F, so each needs its own entry; "horn in B♭" alone is
    # ambiguous (alto and basso are an octave apart), hence no bare alias.
    %{id: :horn_bb_alto, name: "Horn in B♭ alto", family: :brass, clef: :treble, range: nil,
      transposition: :major_second_down,
      aliases: ["bb horn alto", "corno bb alto"]},
    %{id: :horn_bb_basso, name: "Horn in B♭ basso", family: :brass, clef: :treble, range: nil,
      transposition: :major_ninth_down,
      aliases: ["bb horn basso", "corno bb basso"]},
    %{id: :horn_a, name: "Horn in A", family: :brass, clef: :treble, range: nil,
      transposition: :minor_third_down,
      aliases: ["a horn"]},
    %{id: :horn_g, name: "Horn in G", family: :brass, clef: :treble, range: nil,
      transposition: :perfect_fourth_down,
      aliases: ["g horn"]},
    %{id: :horn_e, name: "Horn in E", family: :brass, clef: :treble, range: nil,
      transposition: :minor_sixth_down,
      aliases: ["e horn"]},
    %{id: :horn_d, name: "Horn in D", family: :brass, clef: :treble, range: nil,
      transposition: :minor_seventh_down,
      aliases: ["d horn"]},

    # ── Jazz / rhythm section / pitched percussion ──
    %{id: :c_melody_sax, name: "C Melody Saxophone", family: :woodwind, clef: :treble,
      range: nil, aliases: ["c melody sax", "c tenor sax"]},
    %{id: :xylophone, name: "Xylophone", family: :percussion, clef: :treble, range: {77, 108},
      transposition: :octave_up,
      aliases: ["xyl"]},
    %{id: :glockenspiel, name: "Glockenspiel", family: :percussion, clef: :treble,
      range: {79, 108}, transposition: :two_octaves_up,
      aliases: ["glock", "orchestra bells"]},
    %{id: :celesta, name: "Celesta", family: :keyboard, clef: :treble, range: {60, 108},
      transposition: :octave_up,
      aliases: ["celeste"]},
    %{id: :vibraphone, name: "Vibraphone", family: :percussion, clef: :treble, range: {53, 89},
      aliases: ["vibes", "vibraharp", "vib"]},
    %{id: :marimba, name: "Marimba", family: :percussion, clef: :treble, range: {36, 96},
      aliases: ["mba"]},
    %{id: :tubular_bells, name: "Tubular Bells", family: :percussion, clef: :treble,
      range: nil, aliases: ["chimes"]},
    %{id: :drum_set, name: "Drum Set", family: :percussion, clef: :treble, range: nil,
      aliases: ["drum kit", "drumset", "trap set"]},
    %{id: :electric_piano, name: "Electric Piano", family: :keyboard, clef: :treble,
      range: {28, 103}, aliases: ["rhodes", "epiano", "wurlitzer"]},
    %{id: :accordion, name: "Accordion", family: :keyboard, clef: :treble, range: nil,
      aliases: ["squeezebox"]},
    %{id: :harmonica, name: "Harmonica", family: :woodwind, clef: :treble, range: {60, 96},
      aliases: ["mouth organ", "chromatic harmonica"]}
  ]

  @roster @phase_0 ++ @added

  # Symbolic transposition names keep the roster readable. Each is
  # {direction, base interval, added octaves}; a name the roster uses but
  # this map lacks is a compile error (see the check below) rather than a
  # part that silently comes out at concert pitch.
  #
  # Names are spelled out in full deliberately: abbreviating major and
  # minor to "M" and "m" reads fine until a "m2_down" that actually means
  # a *major* second sends every clarinet part a semitone wrong.
  @transpositions %{
    major_second_down: {:down, :major_second, 0},
    major_second_up: {:up, :major_second, 0},
    minor_third_down: {:down, :minor_third, 0},
    minor_third_up: {:up, :minor_third, 0},
    perfect_fourth_down: {:down, :perfect_fourth, 0},
    perfect_fourth_up: {:up, :perfect_fourth, 0},
    perfect_fifth_down: {:down, :perfect_fifth, 0},
    perfect_fifth_up: {:up, :perfect_fifth, 0},
    minor_sixth_down: {:down, :minor_sixth, 0},
    minor_sixth_up: {:up, :minor_sixth, 0},
    major_sixth_down: {:down, :major_sixth, 0},
    major_sixth_up: {:up, :major_sixth, 0},
    minor_seventh_down: {:down, :minor_seventh, 0},
    minor_seventh_up: {:up, :minor_seventh, 0},
    major_ninth_down: {:down, :major_second, -1},
    major_thirteenth_down: {:down, :major_sixth, -1},
    octave_perfect_fourth_down: {:down, :perfect_fourth, -1},
    two_octaves_major_second_down: {:down, :major_second, -2},
    octave_down: {:down, :unison, -1},
    octave_up: {:up, :unison, 1},
    two_octaves_down: {:down, :unison, -2},
    two_octaves_up: {:up, :unison, 2}
  }

  unknown =
    for entry <- @roster,
        name = Map.get(entry, :transposition),
        not Map.has_key?(@transpositions, name),
        do: {entry.id, name}

  if unknown != [] do
    raise "unknown transposition names in the instrument roster: #{inspect(unknown)}"
  end

  defp resolve_transposition(nil), do: nil

  defp resolve_transposition(name) do
    {direction, base, octaves} = Map.fetch!(@transpositions, name)

    apply(Interval, base, [])
    |> then(fn i -> if direction == :down, do: down(i), else: up(i) end)
    |> Interval.plus_octaves(octaves)
  end

  @entries Map.new(@roster, fn entry ->
             {entry.id,
              %{
                id: entry.id,
                name: entry.name,
                family: entry.family,
                clef: entry.clef,
                range: Map.get(entry, :range),
                transposition: Map.get(entry, :transposition),
                aliases: Map.get(entry, :aliases, [])
              }}
           end)

  @ids Enum.map(@roster, & &1.id)
  @phase_0_ids Enum.map(@phase_0, & &1.id)
  @added_ids Enum.map(@added, & &1.id)

  # Normalized name → id. Display names win over aliases on collision,
  # and earlier roster entries win over later ones, so "Clarinet"
  # resolves to the B♭ clarinet rather than to a keyed variant.
  @lookup (for entry <- Enum.reverse(@roster),
               key <- [entry.name | Map.get(entry, :aliases, [])],
               into: %{} do
             {key
              |> String.downcase()
              |> String.replace("♭", "b")
              |> String.replace("♯", "#")
              |> String.replace(~r/[^a-z0-9#]/u, ""), entry.id}
           end)

  @doc "All instrument ids, in token order (Phase 0 block first)."
  def all, do: @ids

  @doc "Ids frozen in the Phase 0 vocabulary block."
  def phase_0, do: @phase_0_ids

  @doc "Ids added after Phase 0; `Fermata.Vocab` appends these at the end."
  def added, do: @added_ids

  @doc """
  Everything known about an instrument: name, family, clef, transposition
  interval (nil at concert pitch), sounding range, aliases.
  """
  def info(id), do: Map.fetch!(@entries, id)

  def display_name(id), do: info(id).name
  def default_clef(id), do: info(id).clef
  def family(id), do: info(id).family
  def sounding_range(id), do: info(id).range
  def aliases(id), do: info(id).aliases

  @doc """
  The instrument's written → sounding interval, or `nil` at concert pitch.

      iex> Fermata.Instruments.transposition(:clarinet) |> Fermata.Interval.to_string()
      "M2 down"
      iex> Fermata.Instruments.transposition(:violin)
      nil
  """
  def transposition(id), do: info(id).transposition |> resolve_transposition()

  @doc "True if the instrument sounds at a pitch other than written."
  def transposing?(id), do: not is_nil(info(id).transposition)

  @doc "Ids of all transposing instruments."
  def transposing, do: Enum.filter(@ids, &transposing?/1)

  @doc "Ids in a family: `:strings`, `:woodwind`, `:brass`, `:percussion`, `:keyboard`, `:voice`."
  def by_family(family), do: Enum.filter(@ids, &(family(&1) == family))

  @doc "All families present in the roster, in roster order."
  def families, do: @ids |> Enum.map(&family/1) |> Enum.uniq()

  @doc """
  Resolve a free-text name to an id. Case, spacing, punctuation and
  ♭/♯ spelling are ignored, and Humdrum `*I` codes are matched too, so
  `"Cello"`, `"cello"`, `"vlc"` and `"Violoncello"` all land on `:cello`.
  """
  def find(name) when is_binary(name) do
    key =
      name
      |> String.downcase()
      |> String.replace("♭", "b")
      |> String.replace("♯", "#")
      |> String.replace(~r/[^a-z0-9#]/u, "")

    case Map.fetch(@lookup, key) do
      {:ok, id} -> {:ok, id}
      :error -> :error
    end
  end

  @doc """
  Like `find/1` but falls back to `:voice` for unknown names, which is how
  parsers keep ingesting a file whose part names we do not recognise.
  """
  def from_name(name) when is_binary(name) do
    case find(name) do
      {:ok, id} -> id
      :error -> :voice
    end
  end

  def valid?(id), do: Map.has_key?(@entries, id)

  @doc """
  Whether a sounding pitch sits inside the instrument's practical range.
  Instruments with no catalogued range accept everything.
  """
  def in_range?(id, %Fermata.Note{} = note), do: in_range?(id, Pitch.chromatic(note))

  def in_range?(id, midi) when is_integer(midi) do
    case sounding_range(id) do
      nil -> true
      {low, high} -> midi >= low and midi <= high
    end
  end
end
