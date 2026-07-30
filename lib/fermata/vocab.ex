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
    * `{:tuplet, actual, normal}` — modifies the duration just emitted

  Appended after the Phase 0 block (ids 0..526 are frozen: corpus shards
  on disk hold those ids). Appending is safe; reordering is not.
  """

  alias Fermata.{Duration, Instruments, Measure, Note}

  @max_parts 32
  @max_voices 8
  # Each appended block's contents are frozen here by value: computing
  # them from Duration would let a later Duration edit shift every id
  # after the block. New ratios/types/dot-counts append at the very end.
  @frozen_tuplet_ratios [{3, 2}, {5, 4}, {7, 4}, {9, 8}]
  @frozen_types [:breve, :whole, :half, :quarter, :eighth, :"16th", :"32nd", :"64th"]
  @appended_tuplet_ratios [{11, 8}, {13, 8}, {15, 8}]
  @appended_types [:"128th"]
  @appended_extended_ratios [{2, 1}, {2, 3}, {4, 3}, {4, 6}, {5, 2}, {5, 3}, {6, 4}, {7, 1}, {7, 8}]
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

    # Frozen at the original eight types and 0..2 dots; triple dots and
    # later types are appended below, not inserted here, since this list
    # sits inside the frozen id block.
    durations = for type <- @frozen_types, dots <- 0..2, do: {:dur, type, dots}

    phase_0 = specials ++ keys ++ times ++ clefs ++ instruments ++ parts ++ pitches ++ durations

    # APPEND-ONLY past this point — see @moduledoc.
    voices = for v <- 1..@max_voices, do: {:voice, v}
    later_instruments = for i <- Instruments.added(), do: {:instrument, i}
    # The first four ratios are frozen here by value, not taken from
    # Duration: growing Duration.tuplet_ratios/0 in place would shift
    # the triple-dot ids below. Ratios added later append at the end.
    tuplets = for {actual, normal} <- @frozen_tuplet_ratios, do: {:tuplet, actual, normal}
    triple_dots = for type <- @frozen_types, do: {:dur, type, 3}
    later_tuplets = for {actual, normal} <- @appended_tuplet_ratios, do: {:tuplet, actual, normal}
    later_types = for type <- @appended_types, dots <- 0..3, do: {:dur, type, dots}

    extended_tuplets = for {a, n} <- @appended_extended_ratios, do: {:tuplet, a, n}

    known_types = @frozen_types ++ @appended_types
    quad_dots = for type <- known_types, do: {:dur, type, 4}

    # Anything Duration knows that no block above froze lands here, at
    # the global end, in Duration's own (append-only) order.
    known_ratios = @frozen_tuplet_ratios ++ @appended_tuplet_ratios ++ @appended_extended_ratios

    newest_tuplets =
      for {actual, normal} <- Duration.tuplet_ratios() -- known_ratios,
          do: {:tuplet, actual, normal}

    newest_types =
      for type <- Duration.types() -- known_types,
          dots <- 0..Duration.max_dots(),
          do: {:dur, type, dots}

    phase_0 ++
      voices ++
      later_instruments ++
      tuplets ++ triple_dots ++ later_tuplets ++ later_types ++
      extended_tuplets ++ quad_dots ++ newest_tuplets ++ newest_types
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
