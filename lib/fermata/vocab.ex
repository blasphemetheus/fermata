defmodule Fermata.Vocab do
  @moduledoc """
  The enumerated token vocabulary.

  Constructed by enumeration, not learned (no BPE — see PLAN.md §3:
  vanilla BPE degrades multi-track generation quality per SAGE-Music).
  Token ids are assigned by position in `tokens/0`; like the instrument
  roster, the construction order is append-only once training data exists.

  Token forms (internal representation is tagged tuples, ids are ints):

    * `:pad`, `:bos`, `:eos`
    * `{:key, -7..7}`
    * `{:time, beats, beat_type}`
    * `{:clef, clef}`
    * `{:instrument, atom}` — part declaration, in part order
    * `:measure` — measure boundary
    * `{:part, 0..31}` — "the following events belong to part N"
    * `{:pitch, step, alter, octave}`
    * `{:dur, type, dots}`
    * `:chord`, `:tie_start`, `:tie_stop`, `:rest`
  """

  alias Fermata.{Duration, Instruments, Measure, Note}

  @max_parts 32
  @octaves 0..8
  @alters -2..2
  @time_numerators 1..16
  @time_denominators [1, 2, 4, 8, 16, 32]

  def max_parts, do: @max_parts

  @doc "The full token list, in id order."
  def tokens do
    specials = [:pad, :bos, :eos, :measure, :chord, :tie_start, :tie_stop, :rest]
    keys = for fifths <- -7..7, do: {:key, fifths}

    times =
      for n <- @time_numerators, d <- @time_denominators, do: {:time, n, d}

    clefs = for c <- Measure.clefs(), do: {:clef, c}
    instruments = for i <- Instruments.all(), do: {:instrument, i}
    parts = for n <- 0..(@max_parts - 1), do: {:part, n}

    pitches =
      for octave <- @octaves,
          step <- Note.steps(),
          alter <- @alters,
          do: {:pitch, step, alter, octave}

    durations = for type <- Duration.types(), dots <- 0..2, do: {:dur, type, dots}

    specials ++ keys ++ times ++ clefs ++ instruments ++ parts ++ pitches ++ durations
  end

  @doc "Map of token → integer id."
  def token_to_id do
    tokens() |> Enum.with_index() |> Map.new()
  end

  @doc "Map of integer id → token."
  def id_to_token do
    tokens() |> Enum.with_index() |> Map.new(fn {tok, id} -> {id, tok} end)
  end

  def size, do: length(tokens())
end
