defmodule Fermata.MusicXML.Parser do
  @moduledoc """
  Parses the Phase 0 MusicXML subset (score-partwise) back into the IR.

  Handles: part-list names, measures, key/time/clef attributes, notes
  (pitch, chord, ties, dots), rests. Durations are reconstructed from
  `<type>` + `<dot/>` when present (independent of the file's divisions),
  falling back to `<duration>` scaled by the file's `<divisions>`.

  Not yet handled (fine for our own writer's output, needed later for
  PDMX ingestion): `<backup>`/`<forward>` and multi-voice measures,
  tuplets, grace notes.
  """

  @behaviour Saxy.Handler

  alias Fermata.{Duration, Instruments, Measure, Note, Part, Rest, Score}

  def parse(xml) when is_binary(xml) do
    case Saxy.parse_string(xml, __MODULE__, initial_state()) do
      {:ok, state} -> {:ok, build_score(state)}
      {:error, reason} -> {:error, reason}
    end
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
      cur_events: [],
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

    %{state | cur_measure: %Measure{number: number}, cur_events: []}
  end

  defp start_element("note", _attrs, state),
    do: %{state | note: %{dots: 0, ties: [], chord: false, rest: false, alter: 0}}

  defp start_element("chord", _attrs, %{note: note} = state) when not is_nil(note),
    do: put_in(state.note.chord, true)

  defp start_element("rest", _attrs, %{note: note} = state) when not is_nil(note),
    do: put_in(state.note.rest, true)

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
    do: update_measure(state, &%{&1 | time: {String.to_integer(text), elem(&1.time || {0, 4}, 1)}})

  defp end_element("beat-type", text, state),
    do: update_measure(state, &%{&1 | time: {elem(&1.time || {4, 0}, 0), String.to_integer(text)}})

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

  defp end_element("step", text, %{note: note} = state) when not is_nil(note),
    do: put_in(state.note[:step], String.to_existing_atom(text))

  defp end_element("alter", text, %{note: note} = state) when not is_nil(note),
    do: put_in(state.note[:alter], String.to_integer(text))

  defp end_element("octave", text, %{note: note} = state) when not is_nil(note),
    do: put_in(state.note[:octave], String.to_integer(text))

  defp end_element("duration", text, %{note: note} = state) when not is_nil(note),
    do: put_in(state.note[:duration_div], String.to_integer(text))

  defp end_element("type", text, %{note: note} = state) when not is_nil(note),
    do: put_in(state.note[:type], String.to_existing_atom(text))

  defp end_element("note", _text, %{note: note} = state) do
    event = build_event(note, state.divisions)
    %{state | note: nil, cur_events: [event | state.cur_events]}
  end

  defp end_element("measure", _text, %{cur_measure: %Measure{} = m} = state) do
    m = %{m | events: Enum.reverse(state.cur_events), clef: normalize_clef(m.clef)}

    parts = Map.update(state.parts, state.cur_part_id, [m], &[m | &1])
    %{state | parts: parts, cur_measure: nil, cur_events: []}
  end

  defp end_element(_name, _text, state), do: state

  # ── Builders ────────────────────────────────────────────────────────

  defp build_event(%{rest: true} = note, divisions),
    do: %Rest{duration: duration_of(note, divisions)}

  defp build_event(note, divisions) do
    %Note{
      step: Map.fetch!(note, :step),
      alter: note.alter,
      octave: Map.fetch!(note, :octave),
      duration: duration_of(note, divisions),
      chord: note.chord,
      tie: resolve_ties(note.ties)
    }
  end

  defp duration_of(%{type: type, dots: dots}, _divisions), do: {type, dots}

  defp duration_of(%{duration_div: div_count}, divisions) do
    # Scale from the file's divisions to ours, then invert.
    Duration.from_divisions(div(div_count * Duration.divisions(), divisions))
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
