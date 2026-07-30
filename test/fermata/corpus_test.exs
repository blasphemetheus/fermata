defmodule Fermata.CorpusTest do
  use ExUnit.Case, async: true

  alias Fermata.{Corpus, Kern, Tokenizer}

  @chorale "examples/chor001.krn"

  setup do
    dir = Path.join(System.tmp_dir!(), "fermata_corpus_test_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  test "ingest_files packs and reads back exact token ids", %{dir: dir} do
    {:ok, index} = Corpus.ingest_files([@chorale], dir, :kern)

    assert [%{key: "chor001.krn", offset: 0, tokens: n} = entry] = index.entries
    assert index.errors == []

    {:ok, score} = Kern.Parser.parse(File.read!(@chorale))
    expected = Tokenizer.encode_ids(score)
    assert n == length(expected)

    assert Corpus.read_sequence(dir, entry) == expected
  end

  test "ingest_files records parse failures with typed reasons", %{dir: dir} do
    bad = Path.join(System.tmp_dir!(), "bad_#{System.unique_integer([:positive])}.krn")
    # An 11-tuplet: past the ratios the fixed divisions can express, so
    # still refused. (A plain triplet parses now, as does the *^ split
    # this fixture used before either was implemented.)
    File.write!(bad, "**kern\n11c\n*-\n")
    on_exit(fn -> File.rm!(bad) end)

    {:ok, index} = Corpus.ingest_files([@chorale, bad], dir, :kern)

    assert length(index.entries) == 1
    assert [%{reason: _}] = index.errors
    # the good file still round-trips despite the failure before/after it
    assert Corpus.read_sequence(dir, hd(index.entries)) != []
  end

  test "stream_sequences yields decodable sequences", %{dir: dir} do
    {:ok, _} = Corpus.ingest_files([@chorale], dir, :kern)

    [seq] = Corpus.stream_sequences(dir, seed: 42) |> Enum.take(1)
    score = Fermata.from_tokens(seq)
    assert length(score.parts) == 4
  end

  test "stats reports coverage and length percentiles", %{dir: dir} do
    {:ok, _} = Corpus.ingest_files([@chorale], dir, :kern)

    s = Corpus.stats(dir)
    assert s.files_ok == 1
    assert s.files_failed == 0
    assert s.total_tokens == s.length_max
    assert s.length_min == s.length_p50
  end
end
