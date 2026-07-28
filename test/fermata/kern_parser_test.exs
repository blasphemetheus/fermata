defmodule Fermata.Kern.ParserTest do
  use ExUnit.Case, async: true

  alias Fermata.{Kern, Measure, Note, Rest, Tokenizer}

  # SATB chorale phrase in kern: spines low-to-high (bass first), C major,
  # 4/4, with a tie, a chord, a rest, and accidentals.
  @chorale """
  !!!COM: Bach, Johann Sebastian
  !!!OTL: Test Chorale
  **kern\t**kern\t**kern\t**kern
  *I"Bass\t*I"Tenor\t*I"Alto\t*I"Soprano
  *clefF4\t*clefGv2\t*clefG2\t*clefG2
  *k[]\t*k[]\t*k[]\t*k[]
  *M4/4\t*M4/4\t*M4/4\t*M4/4
  =1\t=1\t=1\t=1
  4C\t4G\t4c\t4e
  4C\t4G\t4c\t4e
  4D\t4A\t4d\t4f#
  4G\t4B\t4d\t4g
  =2\t=2\t=2\t=2
  2C 2G\t2c\t[2e\t2g
  4CC\t4c\t2e]\t4.gg
  4r\t4r\t.\t8b-
  ==\t==\t==\t==
  *-\t*-\t*-\t*-
  """

  test "parses the chorale with parts reversed to top-voice-first" do
    assert {:ok, score} = Kern.Parser.parse(@chorale)

    assert score.composer == "Bach, Johann Sebastian"
    assert score.title == "Test Chorale"

    assert Enum.map(score.parts, & &1.instrument) == [:soprano, :alto, :tenor, :bass]
    assert Enum.all?(score.parts, &(length(&1.measures) == 2))
  end

  test "first measure carries key, time, and clef" do
    {:ok, score} = Kern.Parser.parse(@chorale)
    [soprano, _alto, _tenor, bass] = score.parts

    assert %Measure{key: 0, time: {4, 4}, clef: :treble} = hd(soprano.measures)
    assert %Measure{key: 0, time: {4, 4}, clef: :bass} = hd(bass.measures)
    assert %Measure{key: nil, time: nil, clef: nil} = Enum.at(soprano.measures, 1)
  end

  test "pitches, octaves, and accidentals are spelled correctly" do
    {:ok, score} = Kern.Parser.parse(@chorale)
    [soprano, _, _, bass] = score.parts

    # kern lowercase `e` = E4 (c is middle C); `4f#` = F#4
    m1 = hd(soprano.measures)
    assert %Note{step: :E, octave: 4, alter: 0} = Enum.at(m1.events, 0)
    assert %Note{step: :F, octave: 4, alter: 1} = Enum.at(m1.events, 2)

    # `4.gg` = dotted-quarter G5, `8b-` = eighth Bb4
    m2 = Enum.at(soprano.measures, 1)
    assert %Note{step: :G, octave: 5, duration: {:quarter, 1}} = Enum.at(m2.events, 1)
    assert %Note{step: :B, octave: 4, alter: -1, duration: {:eighth, 0}} = Enum.at(m2.events, 2)

    # `4CC` = C2 in the bass (index 2: the `2C 2G` chord occupies 0 and 1)
    bass_m2 = Enum.at(bass.measures, 1)
    assert %Note{step: :C, octave: 2} = Enum.at(bass_m2.events, 2)
  end

  test "ties, chords, rests, and null tokens" do
    {:ok, score} = Kern.Parser.parse(@chorale)
    [_soprano, alto, _tenor, bass] = score.parts

    # Alto: `[2e` then `2e]` — tied pair inside measure 2
    alto_m2 = Enum.at(alto.measures, 1)
    assert %Note{step: :E, tie: :start} = Enum.at(alto_m2.events, 0)
    assert %Note{step: :E, tie: :stop} = Enum.at(alto_m2.events, 1)

    # Alto's `.` null token adds nothing: measure 2 has only the tied pair
    assert length(alto_m2.events) == 2

    # Bass: `2C 2G` chord — second note flagged
    bass_m2 = Enum.at(bass.measures, 1)
    assert [%Note{step: :C, chord: false}, %Note{step: :G, chord: true} | _] = bass_m2.events

    # Bass rest
    assert %Rest{duration: {:quarter, 0}} = List.last(bass_m2.events)
  end

  test "kern output feeds the tokenizer round-trip" do
    {:ok, score} = Kern.Parser.parse(@chorale)
    round_tripped = score |> Tokenizer.encode_ids() |> Tokenizer.decode_ids()

    assert %{round_tripped | title: score.title, composer: score.composer} == score
  end

  test "rejects spine manipulators rather than mis-parsing" do
    kern = """
    **kern\t**kern
    *^\t*
    *-\t*-
    """

    assert {:error, {:unsupported, :spine_manipulation}} = Kern.Parser.parse(kern)
  end

  test "rejects tuplet durations rather than mis-parsing" do
    kern = """
    **kern
    12c
    *-
    """

    assert {:error, {:unsupported_duration, 12}} = Kern.Parser.parse(kern)
  end
end
