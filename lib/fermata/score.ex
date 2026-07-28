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
  """

  defstruct title: nil, composer: nil, parts: []

  @type t :: %__MODULE__{
          title: String.t() | nil,
          composer: String.t() | nil,
          parts: [Fermata.Part.t()]
        }
end

defmodule Fermata.Part do
  @moduledoc "A single part (staff/instrument line) in a score."

  @enforce_keys [:instrument]
  defstruct [:instrument, name: nil, measures: []]

  @type t :: %__MODULE__{
          instrument: atom(),
          name: String.t() | nil,
          measures: [Fermata.Measure.t()]
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
end

defmodule Fermata.Note do
  @moduledoc """
  A spelled note. `chord: true` means this note sounds together with the
  preceding event (MusicXML `<chord/>` semantics). `tie` marks this note
  as tied to the next (`:start`), from the previous (`:stop`), or both.
  """

  @enforce_keys [:step, :octave, :duration]
  defstruct [:step, :octave, :duration, alter: 0, tie: nil, chord: false]

  @type step :: :C | :D | :E | :F | :G | :A | :B
  @type t :: %__MODULE__{
          step: step(),
          alter: -2..2,
          octave: 0..8,
          duration: Fermata.Duration.t(),
          tie: :start | :stop | :both | nil,
          chord: boolean()
        }

  @steps [:C, :D, :E, :F, :G, :A, :B]
  def steps, do: @steps
end

defmodule Fermata.Rest do
  @moduledoc "A rest."

  @enforce_keys [:duration]
  defstruct [:duration]

  @type t :: %__MODULE__{duration: Fermata.Duration.t()}
end

defmodule Fermata.Duration do
  @moduledoc """
  Notated duration: `{type, dots}`, e.g. `{:quarter, 1}` for a dotted
  quarter. Conversion to MusicXML `<duration>` uses a fixed
  `divisions/0` of #{32} per quarter note, which represents every
  binary value from breve to 64th with up to two dots as an integer —
  except the double-dotted 64th, which `divisions_for/1` rejects.
  Tuplets are out of scope for Phase 0.
  """

  @divisions 32

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

  @type type :: :breve | :whole | :half | :quarter | :eighth | :"16th" | :"32nd" | :"64th"
  @type t :: {type(), 0..2}

  def types, do: @types
  def divisions, do: @divisions

  @doc "MusicXML `<duration>` value (in divisions) for a `{type, dots}` pair."
  def divisions_for({type, dots}) when type in @types and dots in 0..2 do
    base = Map.fetch!(@base, type)

    case dots do
      0 -> base
      1 -> ensure_integer(base * 3 / 2, {type, dots})
      2 -> ensure_integer(base * 7 / 4, {type, dots})
    end
  end

  @doc "Inverse of `divisions_for/1`."
  def from_divisions(divs) when is_integer(divs) and divs > 0 do
    Enum.find_value(@types, fn type ->
      base = Map.fetch!(@base, type)

      cond do
        divs == base -> {type, 0}
        divs * 2 == base * 3 -> {type, 1}
        divs * 4 == base * 7 -> {type, 2}
        true -> nil
      end
    end) || raise ArgumentError, "no notated duration for #{divs} divisions"
  end

  defp ensure_integer(value, dur) do
    truncated = trunc(value)

    if truncated * 1.0 == value do
      truncated
    else
      raise ArgumentError, "unrepresentable duration: #{inspect(dur)}"
    end
  end
end
