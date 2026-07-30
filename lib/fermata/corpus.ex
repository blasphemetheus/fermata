defmodule Fermata.Corpus do
  @moduledoc """
  Corpus acquisition and ingestion: download kern/MusicXML sources, parse
  them through the IR, tokenize, and pack token ids into a flat binary for
  training (PLAN.md §5, "Data loading pattern").

  ## Layout

      data/raw/<source>/            # shallow git clone of the source repo
      data/corpus/<source>/
        tokens.bin                  # concatenated sequences, u16 little-endian
        index.etf                   # :erlang.term_to_binary of the index map

  The index holds one entry per successfully ingested file:
  `%{key:, offset:, tokens:}` where `offset` is the BYTE offset into
  tokens.bin and `tokens` the sequence length in token ids (2 bytes each).
  Parse failures are recorded alongside (`%{key:, reason:}`) so coverage is
  measurable, not silent — a file that fails to parse is a statistic, never
  a crash.

  Sequences are read back individually with `:file.pread/2` scatter-gather,
  so training epochs never materialize the whole corpus
  (`stream_sequences/2`).
  """

  alias Fermata.{Kern, MusicXML, Tokenizer, Vocab}

  @raw_dir Path.join("data", "raw")
  @corpus_dir Path.join("data", "corpus")

  @sources %{
    bach_chorales: %{
      repo: "https://github.com/craigsapp/bach-370-chorales",
      glob: "kern/*.krn",
      format: :kern,
      note: "370 four-part chorales — Phase 1 core"
    },
    beethoven_quartets: %{
      repo: "https://github.com/craigsapp/beethoven-string-quartets",
      glob: "kern/*.krn",
      format: :kern,
      note: "stretch source: expect low parse coverage (divisi, tuplets)"
    },
    inventions: %{
      repo: "https://github.com/humdrum-tools/inventions",
      glob: "kern/*.krn",
      format: :kern,
      note: "Bach 2- and 3-part inventions — the most duet-shaped data there is"
    },
    wtc_fugues: %{
      repo: "https://github.com/humdrum-tools/bach-wtc-fugues",
      glob: "kern/*.krn",
      format: :kern,
      note: "WTC fugues with parts pre-split to separate staves"
    },
    haydn_quartets: %{
      repo: "https://github.com/musedata/humdrum-haydn-quartets",
      glob: "kern/*.krn",
      format: :kern,
      note: "210 quartet movements — Phase 2 core"
    },
    mozart_quartets: %{
      repo: "https://github.com/musedata/humdrum-mozart-quartets",
      glob: "kern/*.krn",
      format: :kern,
      note: "82 quartet movements — Phase 2 core"
    },
    polish_scores: %{
      repo: "https://github.com/pl-wnifc/humdrum-polish-scores",
      glob: "**/*.krn",
      format: :kern,
      note: "Polish heritage 1600-1900, ~8.9K files — largest CC BY kern collection"
    }
  }

  def sources, do: @sources

  def raw_dir(source), do: Path.join(@raw_dir, to_string(source))
  def corpus_dir(source), do: Path.join(@corpus_dir, to_string(source))

  @doc """
  Shallow-clone a source repo into `data/raw/<source>`. Idempotent: an
  existing checkout is left untouched.
  """
  def download(source) do
    spec = Map.fetch!(@sources, source)
    dir = raw_dir(source)

    if File.dir?(Path.join(dir, ".git")) do
      {:ok, :already_downloaded}
    else
      File.mkdir_p!(Path.dirname(dir))

      case System.cmd("git", ["clone", "--depth", "1", spec.repo, dir], stderr_to_stdout: true) do
        {_, 0} -> {:ok, :downloaded}
        {out, code} -> {:error, {:git_clone_failed, code, out}}
      end
    end
  end

  @doc """
  Parse + tokenize every file the source's glob matches and pack the token
  ids into `data/corpus/<source>/tokens.bin` (+ index.etf). Rebuilds from
  scratch each run — ingestion is cheap relative to training, and a full
  rebuild keeps offsets trivially consistent.

  Returns `{:ok, index}`.
  """
  def ingest(source) do
    spec = Map.fetch!(@sources, source)
    files = Path.wildcard(Path.join(raw_dir(source), spec.glob)) |> Enum.sort()

    if files == [] do
      {:error, {:no_files, "nothing matches #{spec.glob} under #{raw_dir(source)} — run download first"}}
    else
      ingest_files(files, corpus_dir(source), spec.format)
    end
  end

  @doc """
  Ingest an explicit list of files (kern or MusicXML by `format`) into
  `out_dir`. The unit `ingest/1` is built on; public for tests and ad-hoc
  corpora.
  """
  def ingest_files(files, out_dir, format) do
    File.mkdir_p!(out_dir)
    bin_path = Path.join(out_dir, "tokens.bin")

    {entries, errors, _offset} =
      File.open!(bin_path, [:write, :raw, :binary], fn io ->
        Enum.reduce(files, {[], [], 0}, fn file, {entries, errors, offset} ->
          key = Path.basename(file)

          case tokenize_file(file, format) do
            {:ok, ids} ->
              bin = pack_ids(ids)
              :ok = :file.write(io, bin)
              entry = %{key: key, offset: offset, tokens: length(ids)}
              {[entry | entries], errors, offset + byte_size(bin)}

            {:error, reason} ->
              {entries, [%{key: key, reason: reason} | errors], offset}
          end
        end)
      end)

    index = %{
      version: 1,
      vocab_size: Vocab.size(),
      format: format,
      entries: Enum.reverse(entries),
      errors: Enum.reverse(errors)
    }

    File.write!(Path.join(out_dir, "index.etf"), :erlang.term_to_binary(index))
    {:ok, index}
  end

  defp tokenize_file(file, format) do
    with {:ok, score} <- parse_file(file, format) do
      {:ok, Tokenizer.encode_ids(score)}
    end
  rescue
    e -> {:error, {:crash, e.__struct__}}
  end

  defp parse_file(file, :kern), do: Kern.Parser.parse(File.read!(file))
  defp parse_file(file, :musicxml), do: MusicXML.Parser.parse(File.read!(file))

  @doc "Load a corpus index written by `ingest/1`."
  def load_index(source_or_dir) do
    dir = resolve_dir(source_or_dir)

    with {:ok, bin} <- File.read(Path.join(dir, "index.etf")) do
      {:ok, :erlang.binary_to_term(bin)}
    end
  end

  @doc "Read back the token ids of one index entry via `:file.pread/2`."
  def read_sequence(source_or_dir, %{offset: offset, tokens: n}) do
    dir = resolve_dir(source_or_dir)

    File.open!(Path.join(dir, "tokens.bin"), [:read, :raw, :binary], fn io ->
      {:ok, bin} = :file.pread(io, offset, n * 2)
      unpack_ids(bin)
    end)
  end

  @doc """
  Infinite stream of token-id sequences sampled uniformly from the corpus
  (with replacement) — the replayable-stream shape Axon training wants.
  Holds one raw file handle open for the stream's lifetime; each element
  costs one `:file.pread/2`.
  """
  def stream_sequences(source_or_dir, opts \\ []) do
    dir = resolve_dir(source_or_dir)
    {:ok, index} = load_index(dir)
    entries = index.entries
    n = length(entries)
    if n == 0, do: raise(ArgumentError, "empty corpus at #{dir}")

    if seed = opts[:seed], do: :rand.seed(:exsss, {seed, seed, seed})
    {:ok, io} = :file.open(String.to_charlist(Path.join(dir, "tokens.bin")), [:read, :raw, :binary])
    by_pos = List.to_tuple(entries)

    Stream.repeatedly(fn ->
      entry = elem(by_pos, :rand.uniform(n) - 1)
      {:ok, bin} = :file.pread(io, entry.offset, entry.tokens * 2)
      unpack_ids(bin)
    end)
  end

  @doc "Summary statistics for an ingested corpus (parse coverage + sequence lengths)."
  def stats(source_or_dir) do
    {:ok, index} = load_index(source_or_dir)
    lengths = index.entries |> Enum.map(& &1.tokens) |> Enum.sort()
    n = length(lengths)

    reason_histogram =
      index.errors
      |> Enum.map(fn %{reason: r} -> coarse_reason(r) end)
      |> Enum.frequencies()
      |> Enum.sort_by(fn {_, c} -> -c end)

    %{
      files_ok: n,
      files_failed: length(index.errors),
      failure_reasons: reason_histogram,
      total_tokens: Enum.sum(lengths),
      length_min: List.first(lengths),
      length_p50: percentile(lengths, 0.50),
      length_p90: percentile(lengths, 0.90),
      length_max: List.last(lengths)
    }
  end

  defp percentile([], _), do: nil
  defp percentile(sorted, p), do: Enum.at(sorted, min(round(p * length(sorted)), length(sorted) - 1))

  defp coarse_reason(reason) when is_tuple(reason), do: elem(reason, 0)
  defp coarse_reason(reason) when is_atom(reason), do: reason
  defp coarse_reason(_), do: :other

  defp resolve_dir(source) when is_atom(source), do: corpus_dir(source)
  defp resolve_dir(dir) when is_binary(dir), do: dir

  # u16 little-endian packing — explicit endianness so shards are portable,
  # matching Nx.from_binary(:u16) on every platform we run on.
  defp pack_ids(ids), do: for(id <- ids, into: <<>>, do: <<id::16-little>>)
  defp unpack_ids(bin), do: for(<<id::16-little <- bin>>, do: id)
end
