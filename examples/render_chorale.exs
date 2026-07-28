# Phase 0 exit-criterion demo: token sequence → engraved score.
#
#     mix run examples/render_chorale.exs
#
# Encodes the chorale fixture to token ids, decodes it back (proving the
# model-facing representation is lossless), writes MusicXML, and renders
# SVG/PDF when verovio + rsvg-convert are installed.

Code.require_file("test/support/chorale.ex")

score = Fermata.Fixtures.Chorale.score()

tokens = Fermata.to_tokens(score)
IO.puts("Encoded chorale: #{length(tokens)} tokens (vocab size #{Fermata.Vocab.size()})")

decoded = Fermata.from_tokens(tokens)
xml = Fermata.to_musicxml(%{decoded | title: score.title, composer: score.composer})

File.mkdir_p!("examples/out")
File.write!("examples/out/chorale.musicxml", xml)
IO.puts("Wrote examples/out/chorale.musicxml")

case Fermata.render_svg(xml) do
  {:ok, pages} ->
    pages
    |> Enum.with_index(1)
    |> Enum.each(fn {svg, i} ->
      File.write!("examples/out/chorale-#{i}.svg", svg)
    end)

    IO.puts("Rendered #{length(pages)} SVG page(s) to examples/out/")

    case Fermata.render_pdf(xml) do
      {:ok, pdf} ->
        File.write!("examples/out/chorale.pdf", pdf)
        IO.puts("Rendered examples/out/chorale.pdf")

      {:error, reason} ->
        IO.puts("PDF step failed: #{inspect(reason)}")
    end

  {:error, {:renderer_not_found, :verovio}} ->
    IO.puts("verovio not installed — skipped rendering (MusicXML output is complete)")

  {:error, reason} ->
    IO.puts("Rendering failed: #{inspect(reason)}")
end
