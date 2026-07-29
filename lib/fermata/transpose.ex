defmodule Fermata.Transpose do
  @moduledoc """
  Transposition of scores, parts and key signatures.

  Three things move together and it is a bug to move only some of them:
  the **pitches**, the **key signature**, and (for a transposing
  instrument) the `<transpose>` declaration that tells a reader what the
  written notes will actually sound like. Every function here keeps all
  three consistent.

  ## Concert pitch vs written pitch

  Fermata's IR — and everything the model generates — is at **concert
  pitch** (what you hear). A B♭ clarinet part on paper is at **written
  pitch** (what the player reads), a major second higher. So preparing
  parts for players is a rendering-time step, not a modelling one:

      score                                  # concert pitch, as generated
      |> Fermata.Transpose.to_written(:clarinet)
      |> Fermata.to_musicxml()                # written pitch + <transpose>

  `to_concert/2` is the inverse, for ingesting a written-pitch source.

  ## Arbitrary transposition

  `by_interval/2` moves music by any interval, and `to_key/3` picks the
  interval for you from a target key signature:

      Fermata.Transpose.by_interval(score, Fermata.Interval.minor_third())
      Fermata.Transpose.to_key(score, -3)     # into E♭ major / C minor

  Because pitches are spelled, transposition preserves enharmonic
  identity: transposing F♯ up a minor third gives A, and G♭ up a minor
  third gives B♭♭ — different notes on paper, as they should be.
  """

  alias Fermata.{Instruments, Interval, Measure, Note, Part, Pitch, Score}

  @doc """
  Rewrite concert-pitch music as the part an instrument's player reads.

  Transposes by the *inverse* of the instrument's written → sounding
  interval (a B♭ clarinet sounds a major second low, so its part is
  written a major second high) and records the instrument's transposition
  on the part so the MusicXML carries a `<transpose>` element.

  Concert-pitch instruments are returned unchanged.
  """
  def to_written(%Score{} = score, instrument) do
    %{score | parts: Enum.map(score.parts, &to_written(&1, instrument))}
  end

  def to_written(%Part{} = part, instrument) do
    case Instruments.transposition(instrument) do
      nil ->
        %{part | instrument: instrument, name: Instruments.display_name(instrument)}

      interval ->
        part
        |> by_interval(Interval.negate(interval))
        |> Map.merge(%{
          instrument: instrument,
          name: Instruments.display_name(instrument),
          transpose: interval
        })
    end
  end

  @doc """
  Read a written-pitch part as concert pitch — the inverse of
  `to_written/2`. Clears the part's `<transpose>` declaration, since the
  result no longer needs one.
  """
  def to_concert(%Score{} = score, instrument) do
    %{score | parts: Enum.map(score.parts, &to_concert(&1, instrument))}
  end

  def to_concert(%Part{} = part, instrument) do
    case Instruments.transposition(instrument) do
      nil -> part
      interval -> part |> by_interval(interval) |> Map.put(:transpose, nil)
    end
  end

  @doc """
  Transpose by an arbitrary interval: pitches and key signatures together.

  Works on a `Score`, a `Part`, a `Measure`, or a `Note`.
  """
  def by_interval(target, interval)

  def by_interval(%Score{} = score, %Interval{} = interval) do
    %{score | parts: Enum.map(score.parts, &by_interval(&1, interval))}
  end

  def by_interval(%Part{} = part, %Interval{} = interval) do
    %{part | measures: Enum.map(part.measures, &by_interval(&1, interval))}
  end

  def by_interval(%Measure{} = measure, %Interval{} = interval) do
    %{
      measure
      | key: transpose_key(measure.key, interval),
        events: Enum.map(measure.events, &transpose_event(&1, interval))
    }
  end

  def by_interval(%Note{} = note, %Interval{} = interval),
    do: Pitch.transpose(note, interval)

  defp transpose_event(%Note{} = note, interval), do: Pitch.transpose(note, interval)
  defp transpose_event(other, _interval), do: other

  @doc """
  Transpose a key signature (a `<fifths>` count) by an interval.

  `nil` passes through, since a measure that does not state a key does not
  acquire one. Results outside the writable -7..7 range are respelled
  enharmonically (D♯ major becomes E♭ major) — the alternative is a key
  signature no notation program will render.
  """
  def transpose_key(nil, _interval), do: nil

  def transpose_key(fifths, %Interval{} = interval) when is_integer(fifths) do
    normalize_fifths(fifths + Interval.fifths_delta(interval))
  end

  defp normalize_fifths(fifths) when fifths > 7, do: normalize_fifths(fifths - 12)
  defp normalize_fifths(fifths) when fifths < -7, do: normalize_fifths(fifths + 12)
  defp normalize_fifths(fifths), do: fifths

  @doc """
  Transpose music into a target key signature.

  The interval is derived from the distance along the circle of fifths
  between the score's current key and `target_fifths`. Since any key is
  reachable going up or down, `:direction` chooses:

    * `:nearest` (default) — the smaller move, preferring down on a tie
    * `:up` / `:down` — force the direction

  Raises if the source states no key signature, because then there is
  nothing to transpose *from* — pass an explicit interval instead.
  """
  def to_key(target, target_fifths, opts \\ [])

  def to_key(%Score{} = score, target_fifths, opts) do
    from = source_key(score)
    by_interval(score, key_interval(from, target_fifths, opts))
  end

  def to_key(%Part{} = part, target_fifths, opts) do
    from = part_key(part) || raise ArgumentError, "part states no key signature to transpose from"
    by_interval(part, key_interval(from, target_fifths, opts))
  end

  defp source_key(%Score{parts: parts}) do
    Enum.find_value(parts, &part_key/1) ||
      raise ArgumentError, "score states no key signature to transpose from"
  end

  defp part_key(%Part{measures: measures}) do
    Enum.find_value(measures, fn %Measure{key: key} -> key end)
  end

  @doc """
  The interval that moves music from one key signature to another.

  Both candidate directions are considered; see `to_key/3` for `:direction`.
  """
  def key_interval(from_fifths, to_fifths, opts \\ []) do
    up = tonic_interval(from_fifths, to_fifths, :up)
    down = tonic_interval(from_fifths, to_fifths, :down)

    case Keyword.get(opts, :direction, :nearest) do
      :up -> up
      :down -> down
      :nearest -> if abs(up.chromatic) < abs(down.chromatic), do: up, else: down
    end
  end

  # The interval between the two keys' tonics, in the requested direction.
  defp tonic_interval(from_fifths, to_fifths, direction) do
    {from_step, from_alter} = Pitch.from_fifths(from_fifths)
    {to_step, to_alter} = Pitch.from_fifths(to_fifths)

    # Place both tonics in the same octave, then push the target above or
    # below the source so the interval carries the requested direction.
    base = Interval.between({from_step, from_alter, 4}, {to_step, to_alter, 4})

    case direction do
      :up -> if base.chromatic < 0, do: Interval.plus_octaves(base, 1), else: base
      :down -> if base.chromatic > 0, do: Interval.plus_octaves(base, -1), else: base
    end
  end

  @doc """
  Sounding pitches in `part` that fall outside `instrument`'s practical
  range, as `{measure_number, note}` pairs. Empty list means playable.

  Meant for checking an arrangement before handing it to a player, and as
  the basis for range-constrained sampling later.
  """
  def out_of_range(%Part{} = part, instrument) do
    for %Measure{number: number, events: events} <- part.measures,
        %Note{} = note <- events,
        not Instruments.in_range?(instrument, note),
        do: {number, note}
  end

  def out_of_range(%Score{parts: parts}, instrument),
    do: Enum.flat_map(parts, &out_of_range(&1, instrument))
end
