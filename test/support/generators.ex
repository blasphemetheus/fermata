defmodule Fermata.Generators do
  @moduledoc """
  StreamData generators for random-but-valid scores, used by the
  round-trip property tests. "Valid" means: representable durations
  (no double-dotted 64ths), no `<chord/>` on a measure's first event,
  all parts sharing a measure count with 1-based numbering, and
  same-voice events kept contiguous — the invariants real ingested
  scores also satisfy.

  Measures are sometimes multi-voice, so the round-trip properties cover
  `<backup>`/`<voice>` and `{:voice, n}` rather than only the
  single-voice happy path.
  """

  import StreamData

  alias Fermata.{Duration, Instruments, Measure, Note, Part, Rest, Score}

  def duration do
    bind(member_of(Duration.types()), fn type ->
      bind(integer(0..2), fn dots -> constant({type, dots}) end)
    end)
  end

  @doc """
  A tuplet ratio, or `nil` most of the time. Mixing tuplet and plain
  events freely is intentional: the writer has to recover group extents
  from the ratios, so the properties should hand it ragged input.
  """
  def tuplet do
    frequency([
      {6, constant(nil)},
      {1, member_of(Duration.tuplet_ratios())}
    ])
  end

  def note do
    bind(
      {member_of(Note.steps()), integer(-2..2), integer(0..8), duration(),
       member_of([nil, nil, nil, :start, :stop, :both]), boolean(), tuplet()},
      fn {step, alter, octave, dur, tie, chord, tuplet} ->
        constant(%Note{
          step: step,
          alter: alter,
          octave: octave,
          duration: dur,
          tie: tie,
          chord: chord,
          tuplet: tuplet
        })
      end
    )
  end

  def rest do
    bind({duration(), tuplet()}, fn {dur, tuplet} ->
      constant(%Rest{duration: dur, tuplet: tuplet})
    end)
  end

  def event, do: frequency([{4, note()}, {1, rest()}])

  @doc """
  A measure's events: usually one voice, sometimes two or three. Voice
  groups are emitted contiguously and in ascending order, which is the
  IR's invariant — a generator that interleaved them would be testing
  input the rest of the system is entitled to reject.
  """
  def events do
    bind(frequency([{5, constant(1)}, {2, constant(2)}, {1, constant(3)}]), fn voice_count ->
      1..voice_count
      |> Enum.map(&voice_events(&1))
      |> fixed_list()
      |> bind(fn groups -> constant(List.flatten(groups)) end)
    end)
  end

  defp voice_events(voice) do
    bind(list_of(event(), min_length: 1, max_length: 6), fn events ->
      events
      |> strip_leading_chord()
      |> Enum.map(&%{&1 | voice: voice})
      |> constant()
    end)
  end

  defp strip_leading_chord([%Note{} = first | rest]), do: [%{first | chord: false} | rest]
  defp strip_leading_chord(events), do: events

  def measure(number, first?) do
    attrs =
      if first? do
        {integer(-7..7), time_signature(), member_of(Measure.clefs())}
      else
        {constant(nil), constant(nil), constant(nil)}
      end

    bind({attrs, events()}, fn {{key, time, clef}, evts} ->
      constant(%Measure{number: number, key: key, time: time, clef: clef, events: evts})
    end)
  end

  def time_signature do
    bind({integer(1..16), member_of([1, 2, 4, 8, 16, 32])}, fn {n, d} ->
      constant({n, d})
    end)
  end

  def part(measure_count) do
    bind(member_of(Instruments.all()), fn instrument ->
      measures =
        1..measure_count
        |> Enum.map(fn n -> measure(n, n == 1) end)
        |> fixed_list()

      bind(measures, fn ms ->
        constant(%Part{
          instrument: instrument,
          name: Instruments.display_name(instrument),
          measures: ms
        })
      end)
    end)
  end

  def score do
    bind({integer(1..4), integer(1..4)}, fn {part_count, measure_count} ->
      bind(fixed_list(List.duplicate(part(measure_count), part_count)), fn parts ->
        constant(%Score{title: nil, composer: nil, parts: parts})
      end)
    end)
  end
end
