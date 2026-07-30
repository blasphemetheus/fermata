defmodule Fermata.MusicXML.Parser do
  @moduledoc """
  Parses the Phase 0 MusicXML subset (score-partwise) back into the IR.

  Handles: part-list names, measures, key/time/clef attributes, notes
  (pitch, chord, ties, dots), rests. Durations are reconstructed from
  `<type>` + `<dot/>` when present (independent of the file's divisions),
  falling back to `<duration>` scaled by the file's `<divisions>`.

  Multi-voice measures are read positionally: `<backup>` and `<forward>`
  move a running cursor, every event is recorded at its cursor position,
  and at the measure boundary events regroup per voice (in order of
  first appearance, densely renumbered — MusicXML piano voices are often
  1 and 5). A voice that starts or resumes away from where it left off
  gets the gap padded with rests (`Duration.decompose_rests/1`), which
  is how the IR encodes voice position. Overlapping events inside one
  voice and gaps our divisions cannot express are typed refusals.
  Grace notes are dropped, as in the kern parser. `<staff>` is ignored:
  staff assignment is presentation, voices carry the content.
  """

  @behaviour Saxy.Handler

  alias Fermata.{Duration, Instruments, Measure, Note, Part, Rest, Score}

  def parse(xml) when is_binary(xml) do
    case Saxy.parse_string(xml, __MODULE__, initial_state()) do
      {:ok, state} -> {:ok, build_score(state)}
      {:error, reason} -> {:error, reason}
    end
  catch
    {:refuse, reason} -> {:error, reason}
  end

  def parse!(xml) do
    {:ok, score} = parse(xml)
    score
  end

  defp initial_state do
    %{
      stack: [],
      chars: "",
      title: nil,
      composer: nil,
      creator_type: nil,
      # part-list: id => name, plus declaration order
      part_names: %{},
      part_order: [],
      cur_score_part_id: nil,
      # parts: id => [measures, newest first]
      parts: %{},
      cur_part_id: nil,
      cur_measure: nil,
      # entries {position, duration, event} in file divisions, newest first
      cur_events: [],
      position: 0,
      chord_start: 0,
      note: nil,
      divisions: Duration.divisions()
    }
  end

  # ── Saxy callbacks ──────────────────────────────────────────────────

  @impl true
  def handle_event(:start_document, _prolog, state), do: {:ok, state}

  @impl true
  def handle_event(:end_document, _data, state), do: {:ok, state}

  @impl true
  def handle_event(:start_element, {name, attributes}, state) do
    state = %{state | stack: [name | state.stack], chars: ""}
    {:ok, start_element(name, Map.new(attributes), state)}
  end

  @impl true
  def handle_event(:characters, chars, state) do
    {:ok, %{state | chars: state.chars <> chars}}
  end

  @impl true
  def handle_event(:end_element, name, state) do
    state = end_element(name, String.trim(state.chars), state)
    {:ok, %{state | stack: tl(state.stack), chars: ""}}
  end

  # ── Element handling ────────────────────────────────────────────────

  defp start_element("score-part", attrs, state),
    do: %{state | cur_score_part_id: attrs["id"]}

  defp start_element("part", attrs, state),
    do: %{state | cur_part_id: attrs["id"]}

  defp start_element("measure", attrs, state) do
    number =
      case Integer.parse(attrs["number"] || "") do
        {n, _} -> n
        :error -> length(Map.get(state.parts, state.cur_part_id, [])) + 1
      end

    %{state | cur_measure: %Measure{number: number}, cur_events: [], position: 0, chord_start: 0}
  end

  defp start_element("note", _attrs, state),
    do: %{
      state
      | note: %{
          dots: 0,
          ties: [],
          chord: false,
          rest: false,
          grace: false,
          alter: 0,
          voice: 1,
          actual: nil,
          normal: nil
        }
    }

  defp start_element("chord", _attrs, %{note: note} = state) when not is_nil(note),
    do: put_in(state.note.chord, true)

  defp start_element("rest", _attrs, %{note: note} = state) when not is_nil(note),
    do: put_in(state.note.rest, true)

  defp start_element("grace", _attrs, %{note: note} = state) when not is_nil(note),
    do: put_in(state.note.grace, true)

  defp start_element("tie", attrs, %{note: note} = state) when not is_nil(note),
    do: update_in(state.note.ties, &[attrs["type"] | &1])

  defp start_element("dot", _attrs, %{note: note} = state) when not is_nil(note),
    do: update_in(state.note.dots, &(&1 + 1))

  defp start_element("creator", attrs, state),
    do: %{state | creator_type: attrs["type"]}

  defp start_element(_name, _attrs, state), do: state

  defp end_element("work-title", text, state), do: %{state | title: text}

  defp end_element("creator", text, %{creator_type: "composer"} = state),
    do: %{state | composer: text}

  defp end_element("part-name", text, %{cur_score_part_id: id} = state) when not is_nil(id) do
    %{
      state
      | part_names: Map.put(state.part_names, id, text),
        part_order: [id | state.part_order]
    }
  end

  defp end_element("score-part", _text, state), do: %{state | cur_score_part_id: nil}

  defp end_element("divisions", text, state),
    do: %{state | divisions: String.to_integer(text)}

  defp end_element("fifths", text, state),
    do: update_measure(state, &%{&1 | key: String.to_integer(text)})

  defp end_element("beats", text, state),
    do: update_measure(state, &%{&1 | time: {strict_int(text, :beats), elem(&1.time || {0, 4}, 1)}})

  defp end_element("beat-type", text, state),
    do: update_measure(state, &%{&1 | time: {elem(&1.time || {4, 0}, 0), strict_int(text, :beat_type)}})

  # MuseScore exports composite meters as e.g. <beats>4(2)</beats>;
  # nothing in the IR can hold that, so refuse rather than mis-read it.
  defp strict_int(text, field) do
    case Integer.parse(text) do
      {n, ""} -> n
      _ -> throw({:refuse, {:bad_time, field, text}})
    end
  end

  defp end_element("sign", text, state) do
    if in_element?(state, "clef") do
      update_measure(state, &%{&1 | clef: {text, 2, 0}})
    else
      state
    end
  end

  defp end_element("line", text, state) do
    if in_element?(state, "clef") do
      update_measure(state, fn m ->
        {sign, _line, oct} = m.clef
        %{m | clef: {sign, String.to_integer(text), oct}}
      end)
    else
      state
    end
  end

  defp end_element("clef-octave-change", text, state) do
    update_measure(state, fn m ->
      {sign, line, _oct} = m.clef
      %{m | clef: {sign, line, String.to_integer(text)}}
    end)
  end

  @steps Map.new(~w(A B C D E F G), &{&1, String.to_atom(&1)})
  @type_names Map.new(Fermata.Duration.types(), &{to_string(&1), &1})

  defp end_element("step", text, %{note: note} = state) when not is_nil(note),
    do:
      put_in(
        state.note[:step],
        Map.get(@steps, text) || throw({:refuse, {:bad_step, text}})
      )

  defp end_element("alter", text, %{note: note} = state) when not is_nil(note),
    do: put_in(state.note[:alter], String.to_integer(text))

  defp end_element("octave", text, %{note: note} = state) when not is_nil(note),
    do: put_in(state.note[:octave], String.to_integer(text))

  defp end_element("duration", text, %{note: note} = state) when not is_nil(note),
    do: put_in(state.note[:duration_div], String.to_integer(text))

  # <backup>/<forward> move the measure cursor; their <duration> arrives
  # outside any <note>.
  defp end_element("duration", text, %{note: nil} = state) do
    cond do
      in_element?(state, "backup") -> %{state | position: state.position - String.to_integer(text)}
      in_element?(state, "forward") -> %{state | position: state.position + String.to_integer(text)}
      true -> state
    end
  end

  defp end_element("type", text, %{note: note} = state) when not is_nil(note),
    do:
      put_in(
        state.note[:type],
        Map.get(@type_names, text) || throw({:refuse, {:unsupported_type, text}})
      )

  defp end_element("voice", text, %{note: note} = state) when not is_nil(note),
    do: put_in(state.note[:voice], String.to_integer(text))

  # <time-modification> carries the tuplet ratio. The <tuplet> bracket in
  # <notations> is ignored: it is presentation, and the writer recomputes
  # group extents from the ratios themselves.
  defp end_element("actual-notes", text, %{note: note} = state) when not is_nil(note),
    do: put_in(state.note[:actual], String.to_integer(text))

  defp end_element("normal-notes", text, %{note: note} = state) when not is_nil(note),
    do: put_in(state.note[:normal], String.to_integer(text))

  defp end_element("note", _text, %{note: %{grace: true}} = state),
    do: %{state | note: nil}

  defp end_element("note", _text, %{note: note} = state) do
    dur =
      note[:duration_div] ||
        throw({:refuse, {:missing_duration_element, note[:step] || :rest}})

    # A typeless whole-measure rest in an odd meter (4.5 quarters in
    # 9/8, say) has no single notated value, so build_events may return
    # several rests; they are recorded as one positioned entry.
    events = build_events(note, state.divisions)

    if note.chord do
      # Chord members sound at the chord's start and do not advance.
      %{state | note: nil, cur_events: [{state.chord_start, dur, events} | state.cur_events]}
    else
      %{
        state
        | note: nil,
          cur_events: [{state.position, dur, events} | state.cur_events],
          chord_start: state.position,
          position: state.position + dur
      }
    end
  end

  defp end_element("measure", _text, %{cur_measure: %Measure{} = m} = state) do
    events = state.cur_events |> Enum.reverse() |> regroup_voices(state.divisions)
    m = %{m | events: events, clef: normalize_clef(m.clef)}

    parts = Map.update(state.parts, state.cur_part_id, [m], &[m | &1])
    %{state | parts: parts, cur_measure: nil, cur_events: []}
  end

  defp end_element(_name, _text, state), do: state

  # ── Voice layout ────────────────────────────────────────────────────

  # Rebuild the IR's voice-grouped, contiguous event order (the
  # Measure.voice_groups/1 invariant) from positioned events in document
  # order. Voices keep first-appearance order and are renumbered densely
  # from 1. Within a voice, a positional gap (a <forward>, or a voice
  # entering mid-measure) becomes explicit rests; an overlap is refused.
  defp regroup_voices(entries, file_divisions) do
    entries
    |> Enum.map(fn {_pos, _dur, [event | _]} -> event.voice end)
    |> Enum.uniq()
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {voice, dense} ->
      entries
      |> Enum.filter(fn {_pos, _dur, [event | _]} -> event.voice == voice end)
      |> lay_out_voice(dense, file_divisions)
    end)
  end

  defp lay_out_voice(entries, dense, file_divisions) do
    {events, _expected} =
      Enum.reduce(entries, {[], 0}, fn {pos, dur, events}, {acc, expected} ->
        events = events |> Enum.map(&%{&1 | voice: dense}) |> Enum.reverse()

        cond do
          match?([%Note{chord: true} | _], events) ->
            {events ++ acc, expected}

          pos == expected ->
            {events ++ acc, pos + dur}

          pos > expected ->
            pad = gap_rests(pos - expected, file_divisions, dense)
            {events ++ Enum.reverse(pad, acc), pos + dur}

          true ->
            throw({:refuse, {:overlapping_voice, dense}})
        end
      end)

    Enum.reverse(events)
  end

  defp gap_rests(gap, file_divisions, voice) do
    ours = gap * Duration.divisions()

    with 0 <- rem(ours, file_divisions),
         {:ok, rests} <- Duration.decompose_rests(div(ours, file_divisions)) do
      Enum.map(rests, fn {duration, tuplet} ->
        %Rest{duration: duration, tuplet: tuplet, voice: voice}
      end)
    else
      _ -> throw({:refuse, {:unrepresentable_offset, gap}})
    end
  end

  # ── Builders ────────────────────────────────────────────────────────

  # A rest with a written <type> is one rest. Without one (typeless
  # whole-measure rests) its sounding length may need several written
  # values — 4.5 quarters in 9/8 is a whole plus an eighth.
  defp build_events(%{rest: true, type: _} = note, divisions) do
    [%Rest{duration: duration_of(note, divisions), voice: note.voice, tuplet: tuplet_of(note)}]
  end

  defp build_events(%{rest: true} = note, divisions) do
    ours = note.duration_div * Duration.divisions()

    with 0 <- rem(ours, divisions),
         {:ok, rests} <- Duration.decompose_rests(div(ours, divisions)) do
      for {duration, tuplet} <- rests do
        %Rest{duration: duration, voice: note.voice, tuplet: tuplet}
      end
    else
      _ -> throw({:refuse, {:unrepresentable_rest, note.duration_div}})
    end
  end

  defp build_events(note, divisions) do
    [
      %Note{
        step: Map.fetch!(note, :step),
        alter: note.alter,
        octave: Map.fetch!(note, :octave),
        duration: duration_of(note, divisions),
        chord: note.chord,
        tie: resolve_ties(note.ties),
        voice: note.voice,
        tuplet: tuplet_of(note)
      }
    ]
  end

  defp tuplet_of(%{actual: actual, normal: normal})
       when is_integer(actual) and is_integer(normal),
       do: {actual, normal}

  defp tuplet_of(_note), do: nil

  # <type> is the written value, which is what the IR stores, so a tuplet
  # note needs no unscaling here — the ratio is kept separately.
  defp duration_of(%{type: type, dots: dots}, _divisions), do: {type, dots}

  defp duration_of(%{duration_div: div_count}, divisions) do
    # No <type>: fall back to the sounding length, scaled from the file's
    # divisions to ours. Only correct for plain durations; a note (unlike
    # a rest) cannot be split, so no single match is a refusal.
    ours = div_count * Duration.divisions()

    with 0 <- rem(ours, divisions),
         {type, dots} <- Duration.from_divisions(div(ours, divisions)) do
      {type, dots}
    else
      _ -> throw({:refuse, {:unnotatable_duration, div_count}})
    end
  end

  defp resolve_ties([]), do: nil
  defp resolve_ties(["start"]), do: :start
  defp resolve_ties(["stop"]), do: :stop
  defp resolve_ties(ties) when length(ties) == 2, do: :both

  defp normalize_clef(nil), do: nil
  defp normalize_clef({"G", 2, 0}), do: :treble
  defp normalize_clef({"G", 2, -1}), do: :treble_8vb
  defp normalize_clef({"F", 4, 0}), do: :bass
  defp normalize_clef({"C", 3, 0}), do: :alto
  defp normalize_clef({"C", 4, 0}), do: :tenor
  # French violin clef, percussion, tablature... — not in the IR.
  defp normalize_clef(other), do: throw({:refuse, {:unsupported_clef, other}})

  defp update_measure(%{cur_measure: %Measure{} = m} = state, fun),
    do: %{state | cur_measure: fun.(m)}

  defp update_measure(state, _fun), do: state

  defp in_element?(%{stack: [_self, parent | _]}, name), do: parent == name
  defp in_element?(_state, _name), do: false

  defp build_score(state) do
    part_ids = Enum.reverse(state.part_order)

    parts =
      for id <- part_ids do
        name = Map.fetch!(state.part_names, id)

        %Part{
          instrument: Instruments.from_name(name),
          name: name,
          measures: state.parts |> Map.get(id, []) |> Enum.reverse()
        }
      end

    %Score{title: state.title, composer: state.composer, parts: parts}
  end
end
