defmodule Fermata.VocabTest do
  use ExUnit.Case, async: true

  alias Fermata.Vocab

  test "all tokens are unique" do
    tokens = Vocab.tokens()
    assert length(tokens) == length(Enum.uniq(tokens))
  end

  test "vocab is a few hundred tokens, small enough for a tiny embedding" do
    assert Vocab.size() > 300
    assert Vocab.size() < 1000
  end

  test "token_to_id and id_to_token are inverses" do
    t2i = Vocab.token_to_id()
    i2t = Vocab.id_to_token()

    for {token, id} <- t2i do
      assert i2t[id] == token
    end
  end

  test "id assignment is stable: specials come first, pad is 0" do
    t2i = Vocab.token_to_id()
    assert t2i[:pad] == 0
    assert t2i[:bos] == 1
    assert t2i[:eos] == 2
  end
end
