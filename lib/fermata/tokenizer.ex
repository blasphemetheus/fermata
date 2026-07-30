defmodule Fermata.Tokenizer do
  @moduledoc """
  Score IR ↔ token sequence.

  Measure-interleaved layout (PLAN.md §3): all parts of measure N appear
  together before any of measure N+1, so cross-voice alignment is local —
  the failure mode that sinks naive multi-part text formats (NotaGen and
  MuPT both converged on this fix).

  Sequence shape:

      <bos> {:instrument, ...}+          # part declaration, in order
      :measure
        {:part, 0} [attrs] events...
        {:part, 1} [attrs] events...
      :measure
        ...
      <eos>

  where `[attrs]` are `{:key, _}` / `{:time, _, _}` / `{:clef, _}` tokens,
  present iff set on that `Fermata.Measure`, and an event is:

      [:chord]? {:pitch, s, a, o} {:dur, t, d} [{:tuplet, a, n}]? [:tie_start | :tie_stop]*
      :rest {:dur, t, d} [{:tuplet, a, n}]?

  A `{:tuplet, actual, normal}` token modifies the duration immediately
  before it, so plain music is unaffected.

  Multi-voice measures (divisi, keyboard hands) emit a `{:voice, n}`
  marker before each voice group after the first; voice 1 is implicit, so
  single-voice music tokenizes exactly as it did before voices existed.

  `encode/1` → list of symbolic tokens; `encode_ids/1` → integer ids.
  `decode/1` / `decode_ids/1` invert them. Round-trip is exact.
  """

  alias Fermata.{Measure, Note, Part, Rest, Score, Vocab}

  # ── Encode ──────────────────────────────────────────────────────────

  def encode(%Score{parts: parts}) when parts != [] do
    if length(parts) > Vocab.max_parts() do
      raise ArgumentError, "more than #{Vocab.max_parts()} parts"
    end

    measure_count =
      parts |> Enum.map(&length(&1.measures)) |> Enum.max()

    header = for %Part{instrument: i} <- parts, do: {:instrument, i}

    body =
      for m_idx <- 0..(measure_count - 1),
          tokens <- [[:measure] | encode_measure_column(parts, m_idx)],
          token <- tokens,
          do: token

    [:bos] ++ header ++ body ++ [:eos]
  end

  defp encode_measure_column(parts, m_idx) do
    parts
    |> Enum.with_index()
    |> Enum.map(fn {%Part{measures: measures}, p_idx} ->
      case Enum.at(measures, m_idx) do
        nil -> []
        %Measure{} = m -> [{:part, p_idx} | encode_measure(m)]
      end
    end)
  end

  defp encode_measure(%Measure{} = m) do
    attrs =
      Enum.reject(
        [
          m.key && {:key, m.key},
          m.time && {:time, elem(m.time, 0), elem(m.time, 1)},
          m.clef && {:clef, m.clef}
        ],
        &is_nil/1
      )

    attrs ++ Enum.flat_map(Measure.voice_groups(m), &encode_voice_group/1)
  end

  # Voice 1 is the implicit default, so it needs no marker — which keeps
  # single-voice sequences byte-identical to the pre-voice tokenizer.
  defp encode_voice_group({1, events}), do: Enum.flat_map(events, &encode_event/1)

  defp encode_voice_group({voice, events}),
    do: [{:voice, voice} | Enum.flat_map(events, &encode_event/1)]

  defp encode_event(%Note{} = n) do
    chord = if n.chord, do: [:chord], else: []
    {type, dots} = n.duration

    ties =
      case n.tie do
        nil -> []
        :start -> [:tie_start]
        :stop -> [:tie_stop]
        :both -> [:tie_stop, :tie_start]
      end

    chord ++
      [{:pitch, n.step, n.alter, n.octave}, {:dur, type, dots}] ++ tuplet(n.tuplet) ++ ties
  end

  defp encode_event(%Rest{duration: {type, dots}} = r) do
    [:rest, {:dur, type, dots}] ++ tuplet(r.tuplet)
  end

  defp tuplet(nil), do: []
  defp tuplet({actual, normal}), do: [{:tuplet, actual, normal}]

  def encode_ids(%Score{} = score) do
    mapping = Vocab.token_to_id()
    score |> encode() |> Enum.map(&Map.fetch!(mapping, &1))
  end

  # ── Decode ──────────────────────────────────────────────────────────

  def decode_ids(ids) when is_list(ids) do
    mapping = Vocab.id_to_token()
    ids |> Enum.map(&Map.fetch!(mapping, &1)) |> decode()
  end

  def decode([:bos | rest]) do
    {instruments, rest} = take_while_match(rest, &match?({:instrument, _}, &1))

    parts =
      for {:instrument, i} <- instruments do
        %Part{instrument: i, name: Fermata.Instruments.display_name(i)}
      end

    measures_by_part = decode_measures(rest, %{}, 0, nil, nil, 1)

    parts =
      parts
      |> Enum.with_index()
      |> Enum.map(fn {part, idx} ->
        %{part | measures: Map.get(measures_by_part, idx, [])}
      end)

    %Score{parts: parts}
  end

  # State: acc %{part_idx => [measures, newest first]}, measure_number,
  # current part idx, current measure-under-construction, current voice
  # (reset to 1 at each part column — voice numbering is per measure).
  defp decode_measures([:measure | rest], acc, m_num, cur_part, cur_measure, _voice) do
    acc = flush(acc, cur_part, cur_measure)
    decode_measures(rest, acc, m_num + 1, nil, nil, 1)
  end

  defp decode_measures([{:part, idx} | rest], acc, m_num, cur_part, cur_measure, _voice) do
    acc = flush(acc, cur_part, cur_measure)
    decode_measures(rest, acc, m_num, idx, %Measure{number: m_num}, 1)
  end

  defp decode_measures([:eos], acc, _m_num, cur_part, cur_measure, _voice) do
    acc = flush(acc, cur_part, cur_measure)
    Map.new(acc, fn {idx, measures} -> {idx, Enum.reverse(measures)} end)
  end

  defp decode_measures([{:voice, v} | rest], acc, m_num, cur_part, %Measure{} = m, _voice) do
    decode_measures(rest, acc, m_num, cur_part, m, v)
  end

  defp decode_measures([token | rest], acc, m_num, cur_part, %Measure{} = m, voice) do
    m =
      case token do
        {:key, fifths} -> %{m | key: fifths}
        {:time, n, d} -> %{m | time: {n, d}}
        {:clef, clef} -> %{m | clef: clef}
        :chord -> add_event(m, {:pending_chord})
        {:pitch, s, a, o} -> add_pitch(m, s, a, o, voice)
        {:dur, type, dots} -> set_duration(m, {type, dots}, voice)
        {:tuplet, actual, normal} -> set_tuplet(m, {actual, normal})
        :tie_start -> update_tie(m, :start)
        :tie_stop -> update_tie(m, :stop)
        :rest -> add_event(m, {:pending_rest})
      end

    decode_measures(rest, acc, m_num, cur_part, m, voice)
  end

  # Events are accumulated newest-first in m.events, with in-progress
  # markers replaced as their remaining tokens arrive.
  defp add_event(%Measure{events: events} = m, marker), do: %{m | events: [marker | events]}

  defp add_pitch(%Measure{events: [{:pending_chord} | events]} = m, s, a, o, voice) do
    note = %Note{step: s, alter: a, octave: o, duration: :pending, chord: true, voice: voice}
    %{m | events: [note | events]}
  end

  defp add_pitch(%Measure{events: events} = m, s, a, o, voice) do
    note = %Note{step: s, alter: a, octave: o, duration: :pending, voice: voice}
    %{m | events: [note | events]}
  end

  defp set_duration(%Measure{events: [{:pending_rest} | events]} = m, dur, voice) do
    %{m | events: [%Rest{duration: dur, voice: voice} | events]}
  end

  defp set_duration(%Measure{events: [%Note{duration: :pending} = n | events]} = m, dur, _voice) do
    %{m | events: [%{n | duration: dur} | events]}
  end

  # Applies to whichever event's duration was just set.
  defp set_tuplet(%Measure{events: [event | events]} = m, ratio),
    do: %{m | events: [%{event | tuplet: ratio} | events]}

  defp update_tie(%Measure{events: [%Note{} = n | events]} = m, side) do
    tie =
      case {n.tie, side} do
        {nil, side} -> side
        {:stop, :start} -> :both
        {:start, :stop} -> :both
      end

    %{m | events: [%{n | tie: tie} | events]}
  end

  defp flush(acc, nil, _measure), do: acc

  defp flush(acc, part_idx, %Measure{events: events} = m) do
    Map.update(acc, part_idx, [%{m | events: Enum.reverse(events)}], fn measures ->
      [%{m | events: Enum.reverse(events)} | measures]
    end)
  end

  defp take_while_match(list, fun) do
    taken = Enum.take_while(list, fun)
    {taken, Enum.drop(list, length(taken))}
  end
end
