defmodule Fermata.TokenizerTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Fermata.{Fixtures.Chorale, Generators, Tokenizer}

  describe "chorale fixture" do
    test "encodes to a token list bracketed by bos/eos" do
      tokens = Tokenizer.encode(Chorale.score())
      assert List.first(tokens) == :bos
      assert List.last(tokens) == :eos

      # 4 declared parts, 3 measure boundaries
      assert Enum.count(tokens, &match?({:instrument, _}, &1)) == 4
      assert Enum.count(tokens, &(&1 == :measure)) == 3
    end

    test "round-trips exactly through symbolic tokens" do
      score = Chorale.score()
      round_tripped = score |> Tokenizer.encode() |> Tokenizer.decode()

      assert strip_metadata(round_tripped) == strip_metadata(score)
    end

    test "round-trips exactly through integer ids" do
      score = Chorale.score()
      round_tripped = score |> Tokenizer.encode_ids!() |> Tokenizer.decode_ids()

      assert strip_metadata(round_tripped) == strip_metadata(score)
    end
  end

  property "any valid score round-trips through token ids" do
    check all score <- Generators.score() do
      round_tripped = score |> Tokenizer.encode_ids!() |> Tokenizer.decode_ids()
      assert strip_metadata(round_tripped) == strip_metadata(score)
    end
  end

  describe "typed refusals" do
    alias Fermata.{Measure, Note, Part, Score}

    defp one_measure_score(measure_attrs) do
      note = %Note{step: :C, alter: 0, octave: 4, duration: {:quarter, 0}}
      measure = struct!(Measure, Keyword.merge([number: 1, events: [note]], measure_attrs))
      %Score{parts: [%Part{instrument: :violin, name: "Violin", measures: [measure]}]}
    end

    test "mensural time signature is refused, not crashed" do
      score = one_measure_score(time: {2, 3})
      assert {:error, {:unsupported_time, {2, 3}}} = Tokenizer.encode_ids(score)
    end

    test "key signature beyond seven accidentals is refused" do
      score = one_measure_score(key: 9)
      assert {:error, {:key_out_of_range, 9}} = Tokenizer.encode_ids(score)
    end

    test "more parts than the vocab addresses is refused" do
      part = %Part{instrument: :violin, name: "Violin", measures: []}
      score = %Score{parts: List.duplicate(part, 33)}
      assert {:error, {:too_many_parts, 33}} = Tokenizer.encode_ids(score)
    end

    test "encode_ids! raises the refusal" do
      score = one_measure_score(time: {2, 3})
      assert_raise ArgumentError, ~r/unsupported_time/, fn -> Tokenizer.encode_ids!(score) end
    end
  end

  # Title/composer are not represented in the token stream (deliberate:
  # the model composes music, not metadata), so equality is modulo them.
  defp strip_metadata(score) do
    %{score | title: nil, composer: nil}
  end
end
