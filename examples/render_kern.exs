# Full-pipeline demo on real-world data: kern → IR → tokens → IR → MusicXML → SVG/PDF.
#
#   mix run examples/render_kern.exs path/to/chorale.krn
#
# Get real Bach chorales (370 of them) from:
#   https://github.com/craigsapp/bach-370-chorales
# e.g.
#   curl -sLO https://raw.githubusercontent.com/craigsapp/bach-370-chorales/master/kern/chor001.krn
#   mix run examples/render_kern.exs chor001.krn
#
# Outputs land in examples/out/<basename>.{musicxml,pdf} + <basename>-N.svg

path =
  case System.argv() do
    [p] -> p
    _ -> IO.puts(:stderr, "usage: mix run examples/render_kern.exs <file.krn>") && System.halt(1)
  end

base = Path.basename(path, ".krn")
out_dir = Path.join(["examples", "out"])
File.mkdir_p!(out_dir)

kern = File.read!(path)

score =
  case Fermata.Kern.Parser.parse(kern) do
    {:ok, score} ->
      score

    {:error, reason} ->
      IO.puts(:stderr, "parse failed: #{inspect(reason)}")
      System.halt(1)
  end

IO.puts("Parsed:   #{score.title || base} — #{score.composer || "unknown"}")
IO.puts("Parts:    #{Enum.map_join(score.parts, ", ", & &1.name)}")
IO.puts("Measures: #{length(hd(score.parts).measures)}")

# The round trip the model will live inside: IR → token ids → IR
ids = Fermata.to_tokens(score)
IO.puts("Tokens:   #{length(ids)} (vocab size #{Fermata.Vocab.size()})")
decoded = Fermata.from_tokens(ids)

xml = Fermata.to_musicxml(decoded)
xml_path = Path.join(out_dir, base <> ".musicxml")
File.write!(xml_path, xml)
IO.puts("Wrote #{xml_path}")

case Fermata.render_svg(xml) do
  {:ok, svgs} ->
    svgs
    |> Enum.with_index(1)
    |> Enum.each(fn {svg, i} ->
      File.write!(Path.join(out_dir, "#{base}-#{i}.svg"), svg)
    end)

    IO.puts("Wrote #{length(svgs)} SVG page(s) to #{out_dir}/")

    case Fermata.render_pdf(xml) do
      {:ok, pdf} ->
        pdf_path = Path.join(out_dir, base <> ".pdf")
        File.write!(pdf_path, pdf)
        IO.puts("Wrote #{pdf_path}")

      {:error, reason} ->
        IO.puts("PDF step skipped: #{inspect(reason)}")
    end

  {:error, reason} ->
    IO.puts("Render skipped: #{inspect(reason)}")
end
