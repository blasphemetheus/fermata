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
      round_tripped = score |> Tokenizer.encode_ids() |> Tokenizer.decode_ids()

      assert strip_metadata(round_tripped) == strip_metadata(score)
    end
  end

  property "any valid score round-trips through token ids" do
    check all score <- Generators.score() do
      round_tripped = score |> Tokenizer.encode_ids() |> Tokenizer.decode_ids()
      assert strip_metadata(round_tripped) == strip_metadata(score)
    end
  end

  # Title/composer are not represented in the token stream (deliberate:
  # the model composes music, not metadata), so equality is modulo them.
  defp strip_metadata(score) do
    %{score | title: nil, composer: nil}
  end
end
