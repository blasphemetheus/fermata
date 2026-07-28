defmodule Fermata.Generators do
  @moduledoc """
  StreamData generators for random-but-valid scores, used by the
  round-trip property tests. "Valid" means: representable durations
  (no double-dotted 64ths), no `<chord/>` on a measure's first event,
  and all parts sharing a measure count with 1-based numbering — the
  invariants real ingested scores will also satisfy.
  """

  import StreamData

  alias Fermata.{Duration, Instruments, Measure, Note, Part, Rest, Score}

  def duration do
    bind(member_of(Duration.types()), fn type ->
      max_dots = if type == :"64th", do: 1, else: 2
      bind(integer(0..max_dots), fn dots -> constant({type, dots}) end)
    end)
  end

  def note do
    bind(
      {member_of(Note.steps()), integer(-2..2), integer(0..8), duration(),
       member_of([nil, nil, nil, :start, :stop, :both]), boolean()},
      fn {step, alter, octave, dur, tie, chord} ->
        constant(%Note{
          step: step,
          alter: alter,
          octave: octave,
          duration: dur,
          tie: tie,
          chord: chord
        })
      end
    )
  end

  def rest do
    bind(duration(), fn dur -> constant(%Rest{duration: dur}) end)
  end

  def event, do: frequency([{4, note()}, {1, rest()}])

  def events do
    bind(list_of(event(), min_length: 1, max_length: 8), fn events ->
      constant(strip_leading_chord(events))
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
