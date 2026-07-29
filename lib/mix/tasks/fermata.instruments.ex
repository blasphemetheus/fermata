defmodule Mix.Tasks.Fermata.Instruments do
  @shortdoc "Browse the instrument registry: keys, transpositions, ranges"
  @moduledoc """
  Print the instrument registry as a table.

      mix fermata.instruments                    # everything
      mix fermata.instruments clarinet           # name/alias search
      mix fermata.instruments --family woodwind  # one family
      mix fermata.instruments --transposing      # only transposing instruments
      mix fermata.instruments --aliases          # show the alias lists too

  Columns: token id, display name, family, default clef, transposition
  (written → sounding), the written key signature that concert C major
  becomes for that instrument, and the practical sounding range.

  The "C major becomes" column is the one that matters when handing a
  player their part: concert C major read on a B♭ instrument has to be
  written in D major, and that is what appears there.
  """

  use Mix.Task

  alias Fermata.{Instruments, Interval, Pitch}

  @impl Mix.Task
  def run(argv) do
    {opts, args} =
      OptionParser.parse!(argv,
        strict: [family: :string, transposing: :boolean, aliases: :boolean]
      )

    ids =
      Instruments.all()
      |> filter_family(opts[:family])
      |> filter_transposing(opts[:transposing])
      |> filter_search(List.first(args))

    if ids == [] do
      Mix.shell().info("No instruments matched.")
    else
      print_table(ids, opts[:aliases] || false)
      Mix.shell().info("\n#{length(ids)} instrument(s). Vocab size #{Fermata.Vocab.size()}.")
    end
  end

  defp filter_family(ids, nil), do: ids

  defp filter_family(ids, family) do
    family = String.to_existing_atom(family)
    Enum.filter(ids, &(Instruments.family(&1) == family))
  rescue
    ArgumentError ->
      Mix.shell().error("Unknown family. Known: #{Enum.join(Instruments.families(), ", ")}")
      []
  end

  defp filter_transposing(ids, true), do: Enum.filter(ids, &Instruments.transposing?/1)
  defp filter_transposing(ids, _), do: ids

  defp filter_search(ids, nil), do: ids

  defp filter_search(ids, query) do
    needle = String.downcase(query)

    Enum.filter(ids, fn id ->
      haystack = [Atom.to_string(id), Instruments.display_name(id) | Instruments.aliases(id)]
      Enum.any?(haystack, &String.contains?(String.downcase(&1), needle))
    end)
  end

  defp print_table(ids, show_aliases?) do
    rows = Enum.map(ids, &row/1)
    headers = ["id", "name", "family", "clef", "written → sounding", "C major becomes", "range"]
    widths = column_widths([headers | rows])

    Mix.shell().info(format_row(headers, widths))
    Mix.shell().info(Enum.map_join(widths, "-+-", &String.duplicate("-", &1)))
    Enum.each(rows, &Mix.shell().info(format_row(&1, widths)))

    if show_aliases? do
      Mix.shell().info("\nAliases:")

      Enum.each(ids, fn id ->
        case Instruments.aliases(id) do
          [] -> :ok
          aliases -> Mix.shell().info("  #{id}: #{Enum.join(aliases, ", ")}")
        end
      end)
    end
  end

  defp row(id) do
    interval = Instruments.transposition(id)

    [
      Atom.to_string(id),
      Instruments.display_name(id),
      Atom.to_string(Instruments.family(id)),
      Atom.to_string(Instruments.default_clef(id)),
      if(interval, do: Interval.to_string(interval), else: "concert"),
      written_key(interval),
      range(Instruments.sounding_range(id))
    ]
  end

  # Concert C major, as this instrument's player has to read it.
  defp written_key(nil), do: "C major"

  defp written_key(interval) do
    fifths = Fermata.Transpose.transpose_key(0, Interval.negate(interval))
    {step, alter} = Pitch.from_fifths(fifths)
    "#{step}#{accidental(alter)} major"
  end

  defp accidental(0), do: ""
  defp accidental(n) when n > 0, do: String.duplicate("#", n)
  defp accidental(n), do: String.duplicate("b", -n)

  defp range(nil), do: "—"

  defp range({low, high}), do: "#{note_name(low)}–#{note_name(high)} (#{low}–#{high})"

  # Pitch-class spelling for display only; sharps by convention.
  @names {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
  defp note_name(midi), do: "#{elem(@names, rem(midi, 12))}#{div(midi, 12) - 1}"

  defp column_widths(rows) do
    rows
    |> Enum.zip_with(fn column -> column |> Enum.map(&String.length/1) |> Enum.max() end)
  end

  defp format_row(cells, widths) do
    cells
    |> Enum.zip(widths)
    |> Enum.map_join(" | ", fn {cell, width} -> String.pad_trailing(cell, width) end)
    |> String.trim_trailing()
  end
end
