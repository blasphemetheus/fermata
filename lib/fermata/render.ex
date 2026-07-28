defmodule Fermata.Render do
  @moduledoc """
  Engraving via external renderers, driven over `System.cmd/3`.

  Primary path: Verovio (MusicXML → SVG, single static binary, no display
  server) then rsvg-convert (SVG → PDF). LilyPond is the print-quality
  alternative once installed. MuseScore is deliberately not used —
  MuseScore 4 headless requires Xvfb gymnastics (see PLAN.md §6).

  All functions return `{:error, {:renderer_not_found, name}}` when the
  binary is missing so the rest of the pipeline stays testable on
  machines without renderers installed.
  """

  @doc "SVG binary output for a MusicXML string, via Verovio."
  def to_svg(musicxml, opts \\ []) do
    with {:ok, verovio} <- find(:verovio) do
      in_tmp("fermata-render", fn dir ->
        input = Path.join(dir, "score.musicxml")
        output = Path.join(dir, "score.svg")
        File.write!(input, musicxml)

        args =
          ["-o", output, "--all-pages" | Keyword.get(opts, :extra_args, [])] ++ [input]

        case System.cmd(verovio, args, stderr_to_stdout: true) do
          {_out, 0} -> read_pages(dir, "score", ".svg", output)
          {out, code} -> {:error, {:verovio_failed, code, out}}
        end
      end)
    end
  end

  @doc "PDF binary output: Verovio SVG pages piped through rsvg-convert."
  def to_pdf(musicxml, opts \\ []) do
    with {:ok, rsvg} <- find(:"rsvg-convert"),
         {:ok, svg_pages} <- to_svg(musicxml, opts) do
      in_tmp("fermata-pdf", fn dir ->
        paths =
          svg_pages
          |> Enum.with_index(1)
          |> Enum.map(fn {svg, i} ->
            path = Path.join(dir, "page#{i}.svg")
            File.write!(path, svg)
            path
          end)

        out = Path.join(dir, "score.pdf")

        case System.cmd(rsvg, ["-f", "pdf", "-o", out | paths], stderr_to_stdout: true) do
          {_out, 0} -> {:ok, File.read!(out)}
          {err, code} -> {:error, {:rsvg_failed, code, err}}
        end
      end)
    end
  end

  @doc "Which renderers are available on this machine."
  def available do
    for bin <- [:verovio, :lilypond, :"rsvg-convert"],
        into: %{},
        do: {bin, match?({:ok, _}, find(bin))}
  end

  defp find(name) do
    case System.find_executable(to_string(name)) do
      nil -> {:error, {:renderer_not_found, name}}
      path -> {:ok, path}
    end
  end

  # Verovio writes multi-page scores as score_001.svg, score_002.svg, …;
  # single pages keep the plain name.
  defp read_pages(dir, base, ext, single_path) do
    numbered =
      dir
      |> File.ls!()
      |> Enum.filter(&Regex.match?(~r/^#{base}_\d+#{Regex.escape(ext)}$/, &1))
      |> Enum.sort()
      |> Enum.map(&File.read!(Path.join(dir, &1)))

    cond do
      numbered != [] -> {:ok, numbered}
      File.exists?(single_path) -> {:ok, [File.read!(single_path)]}
      true -> {:error, :no_output_produced}
    end
  end

  defp in_tmp(prefix, fun) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "#{prefix}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)

    try do
      fun.(dir)
    after
      File.rm_rf!(dir)
    end
  end
end
