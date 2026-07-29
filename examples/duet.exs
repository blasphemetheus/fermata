# Arrange two voices of a chorale as a playable duet, with each player's
# part transposed into their instrument's written pitch.
#
#   mix run examples/duet.exs [file.krn] [instrument] [instrument]
#
# Defaults to the bundled Bach chorale as clarinet + cello — the target
# deliverable. Any two registry instruments work:
#
#   mix run examples/duet.exs examples/chor001.krn alto_sax cello
#   mix run examples/duet.exs examples/chor001.krn clarinet_a bassoon
#
# Browse the options with `mix fermata.instruments`.
#
# Outputs examples/out/duet.{musicxml,pdf} + duet-N.svg

alias Fermata.{Instruments, Interval, Part, Score, Transpose}

{path, top_name, bottom_name} =
  case System.argv() do
    [] -> {"examples/chor001.krn", "clarinet", "cello"}
    [p] -> {p, "clarinet", "cello"}
    [p, top, bottom] -> {p, top, bottom}
    _ -> IO.puts(:stderr, "usage: mix run examples/duet.exs [file.krn] [top] [bottom]") && System.halt(1)
  end

resolve = fn name ->
  case Instruments.find(name) do
    {:ok, id} ->
      id

    :error ->
      IO.puts(:stderr, "unknown instrument #{inspect(name)} — try `mix fermata.instruments`")
      System.halt(1)
  end
end

top_inst = resolve.(top_name)
bottom_inst = resolve.(bottom_name)

{:ok, source} = Fermata.Kern.Parser.parse(File.read!(path))

IO.puts("Source:  #{source.title || path} — #{source.composer || "unknown"}")
IO.puts("Parts:   #{Enum.map_join(source.parts, ", ", & &1.name)}")

# Outer voices make the most self-sufficient duet: melody on top, the
# harmonic bass underneath.
[top_part | _] = source.parts
bottom_part = List.last(source.parts)

# The IR — and anything the model generates — is at concert pitch. Each
# player needs their own written part, which is where the instrument's
# transposition comes in.
duet = %Score{
  title: "Duet on #{source.title || Path.basename(path, ".krn")}",
  composer: source.composer,
  parts: [
    Transpose.to_written(top_part, top_inst),
    Transpose.to_written(bottom_part, bottom_inst)
  ]
}

IO.puts("")

Enum.zip([duet.parts, [top_inst, bottom_inst], [top_part, bottom_part]])
|> Enum.each(fn {%Part{} = written, inst, concert} ->
  transposition = Instruments.transposition(inst)

  label =
    if transposition,
      do: "written #{Interval.to_string(Interval.negate(transposition))} (sounds #{Interval.to_string(transposition)})",
      else: "concert pitch"

  IO.puts("#{written.name}: #{label}")

  # Range is checked against the CONCERT part, since the range is what
  # the instrument can sound, not what its player can read.
  case Transpose.out_of_range(%{concert | instrument: inst}, inst) do
    [] ->
      IO.puts("  range: all notes playable")

    offenders ->
      {low, high} = Instruments.sounding_range(inst)
      IO.puts("  range: #{length(offenders)} note(s) outside #{low}..#{high} (MIDI)")

      offenders
      |> Enum.take(5)
      |> Enum.each(fn {measure, note} ->
        IO.puts("    m#{measure}: #{note.step}#{note.alter} octave #{note.octave}")
      end)
  end
end)

out_dir = Path.join(["examples", "out"])
File.mkdir_p!(out_dir)

xml = Fermata.to_musicxml(duet)
xml_path = Path.join(out_dir, "duet.musicxml")
File.write!(xml_path, xml)
IO.puts("\nWrote #{xml_path}")

case Fermata.render_svg(xml) do
  {:ok, svgs} ->
    svgs
    |> Enum.with_index(1)
    |> Enum.each(fn {svg, i} -> File.write!(Path.join(out_dir, "duet-#{i}.svg"), svg) end)

    IO.puts("Wrote #{length(svgs)} SVG page(s) to #{out_dir}/")

    case Fermata.render_pdf(xml) do
      {:ok, pdf} ->
        File.write!(Path.join(out_dir, "duet.pdf"), pdf)
        IO.puts("Wrote #{out_dir}/duet.pdf")

      {:error, reason} ->
        IO.puts("PDF step skipped: #{inspect(reason)}")
    end

  {:error, reason} ->
    IO.puts("Render skipped: #{inspect(reason)}")
end
