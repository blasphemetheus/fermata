defmodule Fermata.Kern.Parser do
  @moduledoc """
  Parses Humdrum `**kern` files (the KernScores/humdrum-data corpora —
  Bach chorales, Beethoven quartets, Haydn symphonies) into the score IR.

  Handles: binary durations, ties, chords, rests, key signatures, meters,
  clefs, `*I"` instrument names, `!!!COM`/`!!!OTL` reference records,
  non-kern companion spines (`**dynam`, `**lyrics`, ... — ignored), and
  divisi spine splits/merges (`*^`, `*v`) as IR voices.

  Still refused rather than silently mangled: spine exchange (`*x`), spine
  addition (`*+`), and non-binary (tuplet) durations. Corpus ingestion
  counts and skips those files.

  ## Spines, columns, parts, voices

  A kern file is a table whose columns can split and merge mid-piece. The
  four terms this module keeps distinct:

    * **column** — one tab-separated field on a line. Columns come and go.
    * **part** — one instrument/staff, identified by the column position
      in the `**kern` header. Stable for the whole file.
    * **voice** — an independent rhythmic stream within a part, created by
      `*^` and retired by `*v`.

  So `*^` does not create a part; it creates a second voice inside one.
  A voice that starts mid-measure gets leading rests so its notes land at
  the right beat, since MusicXML positions voices by accumulated duration.

  Kern lists spines low-to-high (bass leftmost); parts are reversed so
  part 0 is the top voice, matching MusicXML/IR convention.
  """

  alias Fermata.{Duration, Measure, Note, Part, Rest, Score, Vocab}

  @recip_types %{
    0 => :breve,
    1 => :whole,
    2 => :half,
    4 => :quarter,
    8 => :eighth,
    16 => :"16th",
    32 => :"32nd",
    64 => :"64th"
  }

  # Rest values usable for padding a late-starting voice, largest first.
  @pad_units (for type <- Duration.types(), do: {Duration.divisions_for({type, 0}), type})
             |> Enum.sort(:desc)

  def parse(text) when is_binary(text) do
    lines =
      text
      |> String.split(["\n", "\r\n"], trim: true)
      |> Enum.reject(&local_comment?/1)

    {refs, lines} = Enum.split_with(lines, &String.starts_with?(&1, "!!"))

    state = %{columns: nil, parts: %{}, order: [], measure_no: 0}

    case Enum.reduce_while(lines, {:ok, state}, &handle_line/2) do
      {:ok, %{columns: nil}} -> {:error, :no_exclusive_interpretation}
      {:ok, state} -> {:ok, build_score(state, refs)}
      {:error, reason} -> {:error, reason}
    end
  end

  def parse_file(path), do: path |> File.read!() |> parse()

  defp new_part do
    %{
      instrument: nil,
      pending: %{key: nil, time: nil, clef: nil},
      measures: [],
      # voice => events, newest-first
      voices: %{},
      # voice => divisions consumed so far in the current measure
      offsets: %{},
      # voice => divisions offset at which this voice entered the measure
      starts: %{}
    }
  end

  defp local_comment?(line),
    do: String.starts_with?(line, "!") and not String.starts_with?(line, "!!")

  # ── Line dispatch ───────────────────────────────────────────────────

  # Exclusive interpretation: fixes the column layout and the part roster.
  defp handle_line("**" <> _ = line, {:ok, state}) do
    {columns, parts, order} =
      line
      |> String.split("\t")
      |> Enum.reduce({[], %{}, []}, fn field, {columns, parts, order} ->
        if field == "**kern" do
          pid = map_size(parts)

          {[%{kind: :kern, part: pid, voice: 1} | columns], Map.put(parts, pid, new_part()),
           [pid | order]}
        else
          {[%{kind: :other, part: nil, voice: 1} | columns], parts, order}
        end
      end)

    if order == [] do
      {:halt, {:error, {:unsupported_spines, String.split(line, "\t")}}}
    else
      {:cont,
       {:ok,
        %{
          state
          | columns: Enum.reverse(columns),
            parts: parts,
            order: Enum.reverse(order)
        }}}
    end
  end

  defp handle_line(_line, {:ok, %{columns: nil}} = acc), do: {:cont, acc}

  defp handle_line("*" <> _ = line, {:ok, state}) do
    fields = String.split(line, "\t")

    cond do
      Enum.any?(fields, &(&1 == "*-")) ->
        {:cont, {:ok, flush_all(state)}}

      Enum.any?(fields, &(&1 in ["*x", "*+"])) ->
        {:halt, {:error, {:unsupported, :spine_manipulation}}}

      Enum.any?(fields, &(&1 in ["*^", "*v"])) ->
        case remanipulate(state, fields) do
          {:ok, state} -> {:cont, {:ok, state}}
          {:error, reason} -> {:halt, {:error, reason}}
        end

      true ->
        {:cont, {:ok, apply_interpretations(state, fields)}}
    end
  end

  defp handle_line("=" <> _, {:ok, state}), do: {:cont, {:ok, flush_all(state)}}

  defp handle_line(line, {:ok, state}) do
    case consume_data_line(state, String.split(line, "\t")) do
      {:ok, state} -> {:cont, {:ok, state}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  # ── Spine manipulation ──────────────────────────────────────────────

  # Rebuild the column list around `*^` splits and `*v` merges. Walks
  # fields left to right because a merge consumes a *run* of adjacent
  # columns, and one line may contain several independent manipulations.
  defp remanipulate(state, fields) do
    pairs = Enum.zip(state.columns, fields)

    case rebuild_columns(pairs, state, []) do
      {:ok, columns, state} -> {:ok, %{state | columns: Enum.reverse(columns)}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp rebuild_columns([], state, acc), do: {:ok, acc, state}

  defp rebuild_columns([{column, "*^"} | rest], state, acc) do
    case split_column(state, column) do
      {:ok, new_column, state} -> rebuild_columns(rest, state, [new_column, column | acc])
      {:error, reason} -> {:error, reason}
    end
  end

  defp rebuild_columns([{column, "*v"} | rest], state, acc) do
    # Consume the whole run of adjacent *v columns; they collapse into the
    # leftmost one, whose voice survives.
    rest = Enum.drop_while(rest, fn {_col, field} -> field == "*v" end)
    rebuild_columns(rest, state, [column | acc])
  end

  defp rebuild_columns([{column, field} | rest], state, acc) do
    state = update_part(state, column, &interpret(&1, field))
    rebuild_columns(rest, state, [column | acc])
  end

  defp split_column(state, %{kind: :other} = column), do: {:ok, column, state}

  defp split_column(state, %{part: pid} = column) do
    live = for %{part: ^pid} = c <- state.columns, do: c.voice
    voice = Enum.max(live, &>=/2, fn -> 0 end) + 1

    if voice > Vocab.max_voices() do
      {:error, {:unsupported, {:too_many_voices, voice}}}
    else
      # The new voice enters where the parent voice currently is, so its
      # notes get padded to that beat when the measure is flushed.
      offset = get_in(state.parts, [pid, :offsets, column.voice]) || 0

      state =
        state
        |> put_in([:parts, pid, :starts, voice], offset)
        |> put_in([:parts, pid, :offsets, voice], offset)

      {:ok, %{column | voice: voice}, state}
    end
  end

  defp apply_interpretations(state, fields) do
    state.columns
    |> Enum.zip(fields)
    |> Enum.reduce(state, fn {column, field}, state ->
      update_part(state, column, &interpret(&1, field))
    end)
  end

  defp update_part(state, %{kind: :other}, _fun), do: state

  defp update_part(state, %{part: pid}, fun),
    do: update_in(state.parts[pid], fun)

  # ── Interpretations ─────────────────────────────────────────────────

  defp interpret(part, "*I\"" <> name), do: %{part | instrument: name}

  defp interpret(part, "*clef" <> clef) do
    clef =
      case clef do
        "G2" -> :treble
        "Gv2" -> :treble_8vb
        "F4" -> :bass
        "C3" -> :alto
        "C4" -> :tenor
        _ -> nil
      end

    put_in(part.pending.clef, clef)
  end

  defp interpret(part, "*k[" <> sig) do
    accidentals = String.trim_trailing(sig, "]")

    fifths =
      cond do
        accidentals == "" ->
          0

        String.contains?(accidentals, "#") ->
          accidentals |> String.graphemes() |> Enum.count(&(&1 == "#"))

        true ->
          -(accidentals |> String.graphemes() |> Enum.count(&(&1 == "-")))
      end

    put_in(part.pending.key, fifths)
  end

  # *MM120 (metronome) must not match the *M meter clause below.
  defp interpret(part, "*MM" <> _), do: part

  defp interpret(part, "*M" <> meter) do
    case String.split(meter, "/") do
      [n, d] ->
        with {n, ""} <- Integer.parse(n), {d, ""} <- Integer.parse(d) do
          put_in(part.pending.time, {n, d})
        else
          _ -> part
        end

      _ ->
        part
    end
  end

  defp interpret(part, _other), do: part

  # ── Data lines ──────────────────────────────────────────────────────

  defp consume_data_line(state, fields) do
    state.columns
    |> Enum.zip(fields)
    |> Enum.reduce_while({:ok, state}, fn
      {%{kind: :other}, _field}, acc ->
        {:cont, acc}

      {column, field}, {:ok, state} ->
        case parse_data_token(field) do
          {:ok, events} -> {:cont, {:ok, add_events(state, column, events)}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
    end)
  end

  defp add_events(state, _column, []), do: state

  defp add_events(state, %{part: pid, voice: voice}, events) do
    advance =
      events
      |> Enum.reject(&match?(%Note{chord: true}, &1))
      |> Enum.map(&Duration.divisions_for(&1.duration))
      |> Enum.sum()

    state
    |> update_in([:parts, pid, :voices, voice], fn existing ->
      Enum.reverse(events) ++ (existing || [])
    end)
    |> update_in([:parts, pid, :offsets, voice], &((&1 || 0) + advance))
  end

  defp parse_data_token("."), do: {:ok, []}

  defp parse_data_token(token) do
    token
    |> String.split(" ", trim: true)
    |> Enum.reject(&grace_note?/1)
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {note_text, idx}, {:ok, acc} ->
      case parse_note(note_text, idx > 0) do
        {:ok, event} -> {:cont, {:ok, [event | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, events} -> {:ok, Enum.reverse(events)}
      error -> error
    end
  end

  defp grace_note?(note_text),
    do: String.contains?(note_text, "q") or String.contains?(note_text, "Q")

  defp parse_note(text, chord?) do
    with {:ok, duration} <- extract_duration(text) do
      if String.contains?(text, "r") do
        {:ok, %Rest{duration: duration}}
      else
        with {:ok, step, octave} <- extract_pitch(text) do
          {:ok,
           %Note{
             step: step,
             octave: octave,
             alter: extract_alter(text),
             duration: duration,
             tie: extract_tie(text),
             chord: chord?
           }}
        end
      end
    end
  end

  defp extract_duration(text) do
    case Regex.run(~r/(\d+)(\.*)/, text) do
      [_, recip, dots] ->
        recip = String.to_integer(recip)

        case Map.fetch(@recip_types, recip) do
          {:ok, type} -> {:ok, {type, String.length(dots)}}
          :error -> {:error, {:unsupported_duration, recip}}
        end

      nil ->
        {:error, {:missing_duration, text}}
    end
  end

  @steps %{"A" => :A, "B" => :B, "C" => :C, "D" => :D, "E" => :E, "F" => :F, "G" => :G}

  defp extract_pitch(text) do
    case Regex.run(~r/([a-g]+|[A-G]+)/, text) do
      [_, letters] ->
        step = @steps |> Map.fetch!(letters |> String.first() |> String.upcase())
        count = String.length(letters)

        octave =
          if letters =~ ~r/[a-g]/ do
            # c = C4, cc = C5, ...
            3 + count
          else
            # C = C3, CC = C2, ...
            4 - count
          end

        {:ok, step, octave}

      nil ->
        {:error, {:missing_pitch, text}}
    end
  end

  defp extract_alter(text) do
    cond do
      String.contains?(text, "#") -> text |> String.graphemes() |> Enum.count(&(&1 == "#"))
      String.contains?(text, "-") -> -(text |> String.graphemes() |> Enum.count(&(&1 == "-")))
      true -> 0
    end
  end

  defp extract_tie(text) do
    open = String.contains?(text, "[")
    close = String.contains?(text, "]")
    continue = String.contains?(text, "_")

    cond do
      continue -> :both
      open and close -> :both
      open -> :start
      close -> :stop
      true -> nil
    end
  end

  # ── Measure assembly ────────────────────────────────────────────────

  defp flush_all(state) do
    if Enum.all?(state.parts, fn {_pid, part} -> empty_part?(part) end) do
      state
    else
      number = state.measure_no + 1
      parts = Map.new(state.parts, fn {pid, part} -> {pid, flush_part(part, number)} end)
      %{state | parts: parts, measure_no: number}
    end
  end

  defp empty_part?(part), do: Enum.all?(part.voices, fn {_v, events} -> events == [] end)

  defp flush_part(part, number) do
    measure = %Measure{
      number: number,
      key: part.pending.key,
      time: part.pending.time,
      clef: part.pending.clef,
      events: measure_events(part)
    }

    %{
      part
      | voices: %{},
        offsets: %{},
        starts: %{},
        pending: %{key: nil, time: nil, clef: nil},
        measures: [measure | part.measures]
    }
  end

  # Voices are emitted in ascending order and renumbered densely from 1,
  # so a part that used voices 1 and 3 this measure writes 1 and 2 — the
  # numbers only have to be consistent within the measure, and dense
  # numbering keeps them inside the vocab's voice range.
  defp measure_events(part) do
    part.voices
    |> Enum.reject(fn {_v, events} -> events == [] end)
    |> Enum.sort_by(fn {v, _events} -> v end)
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {{voice, events}, dense} ->
      padding = Map.get(part.starts, voice, 0) |> pad_rests(dense)
      padding ++ Enum.map(Enum.reverse(events), &%{&1 | voice: dense})
    end)
  end

  # Leading rests for a voice that entered the measure late. Greedy
  # largest-first; every binary duration is a power of two in divisions,
  # so any offset a tuplet-free file can produce decomposes exactly.
  defp pad_rests(0, _voice), do: []

  defp pad_rests(divisions, voice) do
    {rests, remainder} =
      Enum.reduce(@pad_units, {[], divisions}, fn {unit, type}, {rests, left} ->
        count = div(left, unit)
        {rests ++ List.duplicate(%Rest{duration: {type, 0}, voice: voice}, count),
         rem(left, unit)}
      end)

    if remainder == 0 do
      rests
    else
      # Only reachable via a duration this parser already rejects; a
      # visible mis-alignment beats a silent one.
      raise ArgumentError, "voice offset of #{divisions} divisions is not notatable"
    end
  end

  defp build_score(state, refs) do
    parts =
      state.order
      # kern is low-to-high; IR convention is top voice first
      |> Enum.reverse()
      |> Enum.map(fn pid ->
        part = Map.fetch!(state.parts, pid)

        instrument =
          if part.instrument,
            do: Fermata.Instruments.from_name(part.instrument),
            else: :voice

        %Part{
          instrument: instrument,
          name: part.instrument || Fermata.Instruments.display_name(instrument),
          measures: Enum.reverse(part.measures)
        }
      end)

    %Score{title: ref(refs, "OTL"), composer: ref(refs, "COM"), parts: parts}
  end

  defp ref(refs, code) do
    Enum.find_value(refs, fn line ->
      case Regex.run(~r/^!!!#{code}[^:]*:\s*(.+)$/, line) do
        [_, value] -> String.trim(value)
        nil -> nil
      end
    end)
  end
end
