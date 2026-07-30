defmodule Fermata.Score do
  @moduledoc """
  Canonical score intermediate representation (IR).

  Everything in Fermata flows through this IR: source parsers (MusicXML,
  kern) produce it, the tokenizer encodes/decodes it, and the MusicXML
  writer serializes it for rendering.

  Design invariants:

    * Pitches are **spelled** (`step` + `alter` + `octave`), never MIDI
      numbers — F#4 and Gb4 are distinct.
    * Durations are **notated values** (`{type, dots}`), never ticks.
    * Key/time/clef live on measures and are `nil` except where they are
      (re)stated — matching how notation and MusicXML both work.
    * Events carry a `voice` (1-based). Multiple voices on one staff
      (divisi, keyboard hands) are rhythmically independent streams that
      share a measure. Within a measure, events of the same voice are
      **contiguous** — the tokenizer and MusicXML writer both emit
      voice-grouped and rely on it for exact round-trips.
  """

  defstruct title: nil, composer: nil, parts: []

  @type t :: %__MODULE__{
          title: String.t() | nil,
          composer: String.t() | nil,
          parts: [Fermata.Part.t()]
        }
end

defmodule Fermata.Part do
  @moduledoc """
  A single part (staff/instrument line) in a score.

  `transpose` is set only on a part whose notes are at **written** pitch
  for a transposing instrument; it holds that instrument's written →
  sounding interval, which the MusicXML writer emits as `<transpose>` so
  readers know what the part sounds like. `nil` means the notes are
  already at concert pitch. See `Fermata.Transpose`.
  """

  @enforce_keys [:instrument]
  defstruct [:instrument, name: nil, measures: [], transpose: nil]

  @type t :: %__MODULE__{
          instrument: atom(),
          name: String.t() | nil,
          measures: [Fermata.Measure.t()],
          transpose: Fermata.Interval.t() | nil
        }
end

defmodule Fermata.Measure do
  @moduledoc """
  One measure of one part.

  `key` is circle-of-fifths count (-7..7), `time` is `{beats, beat_type}`,
  `clef` is one of `t:clef/0`. All three are `nil` unless stated in this
  measure (typically the first measure, or at a change).
  """

  defstruct number: 1, key: nil, time: nil, clef: nil, events: []

  @type clef :: :treble | :bass | :alto | :tenor | :treble_8vb
  @type t :: %__MODULE__{
          number: pos_integer(),
          key: -7..7 | nil,
          time: {pos_integer(), pos_integer()} | nil,
          clef: clef() | nil,
          events: [Fermata.Note.t() | Fermata.Rest.t()]
        }

  @clefs [:treble, :bass, :alto, :tenor, :treble_8vb]
  def clefs, do: @clefs

  @doc """
  Events grouped into `{voice, events}` pairs in order of first
  appearance. Since same-voice events are contiguous by IR invariant,
  this is a chunk, not a sort — a measure that violates the invariant
  yields the same voice twice rather than silently merging the groups.
  """
  def voice_groups(%__MODULE__{events: events}) do
    events
    |> Enum.chunk_by(& &1.voice)
    |> Enum.map(fn [first | _] = group -> {first.voice, group} end)
  end
end

defmodule Fermata.Note do
  @moduledoc """
  A spelled note. `chord: true` means this note sounds together with the
  preceding event (MusicXML `<chord/>` semantics). `tie` marks this note
  as tied to the next (`:start`), from the previous (`:stop`), or both.
  `voice` is the 1-based voice within the part's staff.

  `tuplet` is `{actual, normal}` when this note belongs to a tuplet — a
  triplet eighth is `duration: {:eighth, 0}, tuplet: {3, 2}`, meaning
  three of them occupy the time of two. The written duration and the
  ratio are stored separately because that is how notation works and how
  MusicXML represents it; the sounding length is the combination.
  """

  @enforce_keys [:step, :octave, :duration]
  defstruct [:step, :octave, :duration, alter: 0, tie: nil, chord: false, voice: 1, tuplet: nil]

  @type step :: :C | :D | :E | :F | :G | :A | :B
  @type t :: %__MODULE__{
          step: step(),
          alter: -2..2,
          octave: 0..8,
          duration: Fermata.Duration.t(),
          tie: :start | :stop | :both | nil,
          chord: boolean(),
          voice: pos_integer(),
          tuplet: Fermata.Duration.tuplet()
        }

  @steps [:C, :D, :E, :F, :G, :A, :B]
  def steps, do: @steps
end

defmodule Fermata.Rest do
  @moduledoc """
  A rest. `voice` is the 1-based voice within the part's staff, and
  `tuplet` is `{actual, normal}` for a rest inside a tuplet.
  """

  @enforce_keys [:duration]
  defstruct [:duration, voice: 1, tuplet: nil]

  @type t :: %__MODULE__{
          duration: Fermata.Duration.t(),
          voice: pos_integer(),
          tuplet: Fermata.Duration.tuplet()
        }
end

defmodule Fermata.Duration do
  @moduledoc """
  Notated duration: `{type, dots}`, e.g. `{:quarter, 1}` for a dotted
  quarter.

  A duration is what is *written*; how long it sounds also depends on the
  event's tuplet ratio, which lives on the note (mirroring MusicXML,
  where `<time-modification>` is a property of the note rather than of
  its `<type>`). So the sounding length of an event is always
  `divisions_for(duration, tuplet)`, never `divisions_for(duration)`
  alone.

  ## Why `divisions/0` is such an odd number

  MusicXML measures time in integer divisions per quarter note, so the
  constant has to be divisible by every fraction any supported duration
  can produce:

    * 64 covers binary values down to a double-dotted 64th (7/64 of a
      quarter), which is why that duration is now representable — it was
      the one gap when divisions were 32.
    * the LCM of the supported tuplet counts (#{inspect([3, 5, 7, 9, 11, 13, 15])})
      covers dividing a beat into thirds through fifteenths.

  Hence #{64 * 45045} per quarter. It makes for large numbers in the XML
  and costs nothing else — the IR itself stores durations symbolically,
  so divisions only exist at the MusicXML boundary and in internal
  offset arithmetic. Supporting further tuplet counts means adding them
  to `@tuplet_actuals`, at the price of a proportionally larger
  constant. (11 and 13 were added for the polish_scores corpus; 15 was
  free, its factors already being in the LCM.)
  """

  # Tuplet counts we can represent exactly. The conventional partner for
  # each is the largest power of two below it: 3:2, 5:4, ..., 15:8.
  # Append-only: Fermata.Vocab freezes the token ids of the first four
  # and appends the rest at the vocab's end.
  @tuplet_actuals [3, 5, 7, 9, 11, 13, 15]
  @tuplet_ratios [{3, 2}, {5, 4}, {7, 4}, {9, 8}, {11, 8}, {13, 8}, {15, 8}]

  @tuplet_lcm Enum.reduce(@tuplet_actuals, 1, fn a, acc -> div(acc * a, Integer.gcd(acc, a)) end)
  @divisions 64 * @tuplet_lcm

  @types [:breve, :whole, :half, :quarter, :eighth, :"16th", :"32nd", :"64th"]
  @base %{
    breve: @divisions * 8,
    whole: @divisions * 4,
    half: @divisions * 2,
    quarter: @divisions,
    eighth: div(@divisions, 2),
    "16th": div(@divisions, 4),
    "32nd": div(@divisions, 8),
    "64th": div(@divisions, 16)
  }

  @max_dots 3

  @type type :: :breve | :whole | :half | :quarter | :eighth | :"16th" | :"32nd" | :"64th"
  @type t :: {type(), 0..3}
  @type tuplet :: {pos_integer(), pos_integer()} | nil

  def types, do: @types
  def divisions, do: @divisions
  def max_dots, do: @max_dots

  @doc "Tuplet `{actual, normal}` ratios the vocabulary and writer support."
  def tuplet_ratios, do: @tuplet_ratios

  @doc "Tuplet actual-counts that can be represented exactly."
  def tuplet_actuals, do: @tuplet_actuals

  @doc """
  MusicXML `<duration>` value (in divisions) for a written duration,
  optionally scaled by a tuplet ratio.

  A triplet eighth is written as an eighth but sounds for two thirds of
  one, so `{3, 2}` scales by `normal / actual`.
  """
  def divisions_for(duration, tuplet \\ nil)

  def divisions_for(duration, tuplet) do
    case exact_divisions(duration, tuplet) do
      {:ok, divs} ->
        divs

      :error ->
        raise ArgumentError, "unrepresentable duration: #{inspect({duration, tuplet})}"
    end
  end

  @doc """
  Whether a duration and tuplet ratio land on a whole number of divisions.

  Parsers call this to reject music they would otherwise have to round —
  a triple-dotted 64th, say, or an 11-tuplet — and turn it into a typed
  error instead of a crash deep in the arithmetic.
  """
  def exact?(duration, tuplet \\ nil), do: match?({:ok, _}, exact_divisions(duration, tuplet))

  # Each dot adds half of what came before, so n dots multiply a duration
  # by (2^(n+1) - 1) / 2^n: 3/2, 7/4, 15/8. Kept as one exact integer
  # ratio (never floats) so representability is a remainder check.
  defp exact_divisions({type, dots}, tuplet)
       when type in @types and is_integer(dots) and dots >= 0 and dots <= @max_dots do
    base = Map.fetch!(@base, type)
    numerator = base * (Integer.pow(2, dots + 1) - 1)
    denominator = Integer.pow(2, dots)

    {numerator, denominator} =
      case tuplet do
        nil ->
          {numerator, denominator}

        {actual, normal} when is_integer(actual) and is_integer(normal) and actual > 0 and normal > 0 ->
          {numerator * normal, denominator * actual}
      end

    if rem(numerator, denominator) == 0 do
      {:ok, div(numerator, denominator)}
    else
      :error
    end
  end

  defp exact_divisions(_duration, _tuplet), do: :error

  @doc """
  Inverse of `divisions_for/1` for *plain* durations.

  Returns `nil` rather than raising when no notated value matches, which
  is how the MusicXML writer detects that a run of tuplet notes has
  filled a whole written value and the tuplet bracket should close.
  """
  def from_divisions(divs) when is_integer(divs) and divs > 0 do
    Enum.find_value(@types, fn type ->
      Enum.find_value(0..@max_dots, fn dots ->
        case exact_divisions({type, dots}, nil) do
          {:ok, ^divs} -> {type, dots}
          _ -> nil
        end
      end)
    end)
  end

  @doc "Like `from_divisions/1` but raises when nothing matches."
  def from_divisions!(divs) do
    from_divisions(divs) || raise ArgumentError, "no notated duration for #{divs} divisions"
  end
end
