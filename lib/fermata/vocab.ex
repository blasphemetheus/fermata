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
    * `{:voice, 1..8}` — "the following events are voice N of this part"

  Appended after the Phase 0 block (ids 0..526 are frozen: corpus shards
  on disk hold those ids). Appending is safe; reordering is not.
  """

  alias Fermata.{Duration, Instruments, Measure, Note}

  @max_parts 32
  @max_voices 8
  @octaves 0..8
  @alters -2..2
  @time_numerators 1..16
  @time_denominators [1, 2, 4, 8, 16, 32]

  def max_parts, do: @max_parts
  def max_voices, do: @max_voices

  @doc "The full token list, in id order."
  def tokens do
    specials = [:pad, :bos, :eos, :measure, :chord, :tie_start, :tie_stop, :rest]
    keys = for fifths <- -7..7, do: {:key, fifths}

    times =
      for n <- @time_numerators, d <- @time_denominators, do: {:time, n, d}

    clefs = for c <- Measure.clefs(), do: {:clef, c}
    # Only the frozen Phase 0 instruments sit here. Instruments added
    # later append at the very end, because inserting a token *inside*
    # this block would shift the id of every pitch and duration token
    # after it — silently invalidating corpora and any trained embedding.
    instruments = for i <- Instruments.phase_0(), do: {:instrument, i}
    parts = for n <- 0..(@max_parts - 1), do: {:part, n}

    pitches =
      for octave <- @octaves,
          step <- Note.steps(),
          alter <- @alters,
          do: {:pitch, step, alter, octave}

    durations = for type <- Duration.types(), dots <- 0..2, do: {:dur, type, dots}

    phase_0 = specials ++ keys ++ times ++ clefs ++ instruments ++ parts ++ pitches ++ durations

    # APPEND-ONLY past this point — see @moduledoc.
    voices = for v <- 1..@max_voices, do: {:voice, v}
    later_instruments = for i <- Instruments.added(), do: {:instrument, i}

    phase_0 ++ voices ++ later_instruments
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
