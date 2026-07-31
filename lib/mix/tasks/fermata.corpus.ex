defmodule Mix.Tasks.Fermata.Corpus do
  @shortdoc "Download and ingest a training corpus (see Fermata.Corpus)"

  @moduledoc """
  Manage training corpora.

      mix fermata.corpus              # list known sources and their status
      mix fermata.corpus bach_chorales  # download + ingest + print stats

  Downloads are shallow git clones under data/raw/; ingestion packs token
  ids into data/corpus/<source>/tokens.bin (+ index.etf). Both directories
  are gitignored.
  """

  use Mix.Task

  alias Fermata.Corpus

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      [] ->
        list()

      [name] ->
        case Enum.find(Map.keys(Corpus.sources()), &(to_string(&1) == name)) do
          nil -> Mix.raise("unknown source #{name} — run `mix fermata.corpus` to list sources")
          source -> build(source)
        end

      _ ->
        Mix.raise("usage: mix fermata.corpus [source]")
    end
  end

  defp list do
    Mix.shell().info("Known sources:\n")

    Enum.each(Corpus.sources(), fn {name, spec} ->
      status =
        cond do
          File.exists?(Path.join(Corpus.corpus_dir(name), "index.etf")) -> ingested_status(name)
          File.dir?(Corpus.raw_dir(name)) -> "downloaded, not ingested"
          true -> "not downloaded"
        end

      Mix.shell().info("  #{name}  [#{status}]")
      Mix.shell().info("    #{spec.repo}  (#{spec.note})")
    end)

    Mix.shell().info("\nBuild one with: mix fermata.corpus <source>")
  end

  defp ingested_status(name) do
    s = Corpus.stats(name)
    "ingested: #{s.files_ok} files, #{s.total_tokens} tokens"
  end

  defp build(source) do
    Mix.shell().info("Downloading #{source}...")

    case Corpus.download(source) do
      {:ok, how} -> Mix.shell().info("  #{how}")
      {:error, reason} -> Mix.raise("download failed: #{inspect(reason)}")
    end

    Mix.shell().info("Ingesting...")

    case Corpus.ingest(source) do
      {:ok, _index} -> print_stats(Corpus.stats(source))
      {:error, reason} -> Mix.raise("ingest failed: #{inspect(reason)}")
    end
  end

  defp print_stats(s) do
    total = s.files_ok + s.files_failed
    pct = if total > 0, do: Float.round(100 * s.files_ok / total, 1), else: 0.0

    Mix.shell().info("""

    Parse coverage: #{s.files_ok}/#{total} files (#{pct}%)
    Total tokens:   #{s.total_tokens}
    Seq length:     min #{s.length_min} · p50 #{s.length_p50} · p90 #{s.length_p90} · max #{s.length_max}
    """)

    if s.failure_reasons != [] do
      Mix.shell().info("Failures by reason:")

      Enum.each(s.failure_reasons, fn {reason, count} ->
        Mix.shell().info("  #{count}  #{inspect(reason)}")
      end)
    end
  end
end
