defmodule Fermata.Kern.Parser do
  @moduledoc """
  Parses Humdrum `**kern` files (the KernScores/humdrum-data corpora —
  Bach chorales, Haydn symphonies, etc.) into the score IR.

  Phase 0 subset: one voice per spine, binary durations, ties, chords,
  rests, key signatures, meters, clefs, `*I"` instrument names, and
  `!!!COM`/`!!!OTL` reference records. Files using spine manipulators
  (`*^`, `*v`, `*x`, `*+`) or non-binary (tuplet) durations return an
  error rather than a silently wrong score — corpus ingestion can then
  count and skip them.

  Kern lists spines low-to-high (bass leftmost); parts are reversed so
  part 0 is the top voice, matching MusicXML/IR convention.
  """

  alias Fermata.{Measure, Note, Part, Rest, Score}

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

  @spine_manipulators ["*^", "*v", "*x", "*+"]

  def parse(text) when is_binary(text) do
    lines =
      text
      |> String.split(["\n", "\r\n"], trim: true)
      |> Enum.reject(&local_comment?/1)

    {refs, lines} = Enum.split_with(lines, &String.starts_with?(&1, "!!"))

    with {:ok, spine_count} <- spine_count(lines),
         :ok <- check_manipulators(lines) do
      state = %{
        spines: List.duplicate(new_spine(), spine_count),
        measure_no: 0
      }

      case Enum.reduce_while(lines, {:ok, state}, &handle_line/2) do
        {:ok, state} -> {:ok, build_score(state, refs)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def parse_file(path), do: path |> File.read!() |> parse()

  defp new_spine do
    %{
      instrument: nil,
      pending: %{key: nil, time: nil, clef: nil},
      events: [],
      measures: []
    }
  end

  defp local_comment?(line),
    do: String.starts_with?(line, "!") and not String.starts_with?(line, "!!")

  defp spine_count(lines) do
    case Enum.find(lines, &String.starts_with?(&1, "**")) do
      nil ->
        {:error, :no_exclusive_interpretation}

      header ->
        fields = String.split(header, "\t")

        if Enum.all?(fields, &(&1 == "**kern")) do
          {:ok, length(fields)}
        else
          {:error, {:unsupported_spines, fields}}
        end
    end
  end

  defp check_manipulators(lines) do
    has_manipulator =
      lines
      |> Enum.filter(&String.starts_with?(&1, "*"))
      |> Enum.any?(fn line ->
        line |> String.split("\t") |> Enum.any?(&(&1 in @spine_manipulators))
      end)

    if has_manipulator, do: {:error, {:unsupported, :spine_manipulation}}, else: :ok
  end

  # ── Line dispatch ───────────────────────────────────────────────────

  defp handle_line("**" <> _, {:ok, state}), do: {:cont, {:ok, state}}

  defp handle_line("*" <> _ = line, {:ok, state}) do
    fields = String.split(line, "\t")

    if Enum.any?(fields, &(&1 == "*-")) do
      {:cont, {:ok, flush_all(state)}}
    else
      spines =
        state.spines
        |> Enum.zip(fields)
        |> Enum.map(fn {spine, field} -> interpret(spine, field) end)

      {:cont, {:ok, %{state | spines: spines}}}
    end
  end

  defp handle_line("=" <> _, {:ok, state}), do: {:cont, {:ok, flush_all(state)}}

  defp handle_line(line, {:ok, state}) do
    fields = String.split(line, "\t")

    result =
      state.spines
      |> Enum.zip(fields)
      |> reduce_ok(fn {spine, field} ->
        case parse_data_token(field) do
          {:ok, events} -> {:ok, %{spine | events: events ++ spine.events}}
          {:error, reason} -> {:error, reason}
        end
      end)

    case result do
      {:ok, spines} -> {:cont, {:ok, %{state | spines: spines}}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp reduce_ok(pairs, fun) do
    Enum.reduce_while(pairs, {:ok, []}, fn pair, {:ok, acc} ->
      case fun.(pair) do
        {:ok, spine} -> {:cont, {:ok, [spine | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, spines} -> {:ok, Enum.reverse(spines)}
      error -> error
    end
  end

  # ── Interpretations ─────────────────────────────────────────────────

  defp interpret(spine, "*I\"" <> name), do: %{spine | instrument: name}

  defp interpret(spine, "*clef" <> clef) do
    clef =
      case clef do
        "G2" -> :treble
        "Gv2" -> :treble_8vb
        "F4" -> :bass
        "C3" -> :alto
        "C4" -> :tenor
        _ -> nil
      end

    put_in(spine.pending.clef, clef)
  end

  defp interpret(spine, "*k[" <> sig) do
    accidentals = String.trim_trailing(sig, "]")

    fifths =
      cond do
        accidentals == "" -> 0
        String.contains?(accidentals, "#") -> accidentals |> String.graphemes() |> Enum.count(&(&1 == "#"))
        true -> -(accidentals |> String.graphemes() |> Enum.count(&(&1 == "-")))
      end

    put_in(spine.pending.key, fifths)
  end

  # *MM120 (metronome) must not match the *M meter clause below.
  defp interpret(spine, "*MM" <> _), do: spine

  defp interpret(spine, "*M" <> meter) do
    case String.split(meter, "/") do
      [n, d] ->
        with {n, ""} <- Integer.parse(n), {d, ""} <- Integer.parse(d) do
          put_in(spine.pending.time, {n, d})
        else
          _ -> spine
        end

      _ ->
        spine
    end
  end

  defp interpret(spine, _other), do: spine

  # ── Data tokens ─────────────────────────────────────────────────────

  defp parse_data_token("."), do: {:ok, []}

  defp parse_data_token(token) do
    notes = String.split(token, " ", trim: true)

    notes
    |> Enum.reject(&grace_note?/1)
    |> Enum.with_index()
    |> reduce_ok(fn {note_text, idx} ->
      case parse_note(note_text, idx > 0) do
        {:ok, event} -> {:ok, event}
        {:error, reason} -> {:error, reason}
      end
    end)
    |> case do
      # Events accumulate newest-first in spines, so reverse chord order here.
      {:ok, events} -> {:ok, Enum.reverse(events)}
      error -> error
    end
  end

  defp grace_note?(note_text),
    do: String.contains?(note_text, "q") or String.contains?(note_text, "Q")

  defp parse_note(text, chord?) do
    with {:ok, duration} <- extract_duration(text) do
      cond do
        String.contains?(text, "r") ->
          {:ok, %Rest{duration: duration}}

        true ->
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

  defp extract_pitch(text) do
    case Regex.run(~r/([a-g]+|[A-G]+)/, text) do
      [_, letters] ->
        step = letters |> String.first() |> String.upcase() |> String.to_existing_atom()
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
    if Enum.all?(state.spines, &(&1.events == [])) do
      state
    else
      number = state.measure_no + 1

      spines =
        Enum.map(state.spines, fn spine ->
          measure = %Measure{
            number: number,
            key: spine.pending.key,
            time: spine.pending.time,
            clef: spine.pending.clef,
            events: Enum.reverse(spine.events)
          }

          %{
            spine
            | events: [],
              pending: %{key: nil, time: nil, clef: nil},
              measures: [measure | spine.measures]
          }
        end)

      %{state | spines: spines, measure_no: number}
    end
  end

  defp build_score(state, refs) do
    parts =
      state.spines
      # kern is low-to-high; IR convention is top voice first
      |> Enum.reverse()
      |> Enum.map(fn spine ->
        instrument =
          if spine.instrument,
            do: Fermata.Instruments.from_name(spine.instrument),
            else: :voice

        %Part{
          instrument: instrument,
          name: spine.instrument || Fermata.Instruments.display_name(instrument),
          measures: Enum.reverse(spine.measures)
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
