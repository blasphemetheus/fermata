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

  # Corpus shards on disk store these ids; if any of these assertions
  # fires, a vocab edit inserted rather than appended and every packed
  # corpus (and any trained embedding) is silently corrupt.
  test "frozen ids never move" do
    t2i = Vocab.token_to_id()

    # end of the phase_0 block
    assert t2i[{:dur, :"64th", 2}] == 526
    # appended blocks, in append order: voices, instruments, the first
    # four tuplet ratios, triple dots
    assert t2i[{:voice, 1}] == 527
    assert t2i[{:tuplet, 3, 2}] == 601
    assert t2i[{:tuplet, 9, 8}] == 604
    assert t2i[{:dur, :breve, 3}] == 605
    assert t2i[{:dur, :"64th", 3}] == 612
    # tuplet ratios added later append after everything above
    assert t2i[{:tuplet, 11, 8}] == 613
    assert t2i[{:tuplet, 13, 8}] == 614
    assert t2i[{:tuplet, 15, 8}] == 615
  end
end
