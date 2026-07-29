defmodule Fermata.MusicXMLTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Fermata.{Fixtures.Chorale, Generators, Instruments, Measure, MusicXML, Note, Part, Rest,
                 Score, Transpose}

  defp note(step, octave, voice, dur \\ {:quarter, 0}),
    do: %Note{step: step, octave: octave, duration: dur, voice: voice}

  describe "writer" do
    test "emits score-partwise 4.0 with all parts declared" do
      xml = MusicXML.Writer.to_xml(Chorale.score())

      assert xml =~ ~s(<score-partwise version="4.0">)
      assert xml =~ "<part-name>Soprano</part-name>"
      assert xml =~ "<part-name>Bass</part-name>"
      assert xml =~ ~s(<part id="P4">)
      assert xml =~ "<fifths>0</fifths>"
      assert xml =~ "<beats>4</beats>"
    end

    test "escapes XML-significant characters in metadata" do
      score = %{Chorale.score() | title: "Airs & <Graces>"}
      xml = MusicXML.Writer.to_xml(score)

      assert xml =~ "Airs &amp; &lt;Graces&gt;"
      refute xml =~ "Airs & <Graces>"
    end
  end

  describe "multi-voice output" do
    test "single-voice measures carry no <voice> or <backup> at all" do
      xml = MusicXML.Writer.to_xml(Chorale.score())

      refute xml =~ "<voice>"
      refute xml =~ "<backup>"
    end

    test "two voices are labelled and separated by a rewind of voice 1's length" do
      score = %Score{
        parts: [
          %Part{
            instrument: :piano,
            name: "Piano",
            measures: [
              %Measure{
                number: 1,
                key: 0,
                time: {2, 4},
                clef: :treble,
                events: [
                  note(:C, 4, 1),
                  note(:D, 4, 1),
                  note(:G, 3, 2),
                  %Rest{duration: {:quarter, 0}, voice: 2}
                ]
              }
            ]
          }
        ]
      }

      xml = MusicXML.Writer.to_xml(score)

      assert xml =~ "<voice>1</voice>"
      assert xml =~ "<voice>2</voice>"
      # Two quarters at 32 divisions each
      assert xml =~ "<backup><duration>64</duration></backup>"
    end
  end

  describe "transposing parts" do
    test "declare <transpose> once, in the first measure" do
      written =
        %Score{parts: [%Part{instrument: :flute, name: "Flute", measures: Chorale.score().parts |> hd() |> Map.fetch!(:measures)}]}
        |> Transpose.to_written(:clarinet)

      xml = MusicXML.Writer.to_xml(written)

      # written -> sounding for a Bb clarinet, in conventional form
      assert xml =~ "<transpose><diatonic>-1</diatonic><chromatic>-2</chromatic></transpose>"
      assert length(String.split(xml, "<transpose>")) == 2
    end

    test "concert-pitch parts declare nothing" do
      xml = MusicXML.Writer.to_xml(Chorale.score())
      refute xml =~ "<transpose>"
    end

    test "wide transpositions use <octave-change>" do
      written = Transpose.to_written(Chorale.score(), :bass_clarinet)
      xml = MusicXML.Writer.to_xml(written)

      assert xml =~ "<octave-change>-1</octave-change>"
      assert Instruments.transposition(:bass_clarinet).chromatic == -14
    end
  end

  describe "round-trip" do
    test "chorale fixture survives write → parse exactly" do
      score = Chorale.score()
      assert {:ok, parsed} = score |> MusicXML.Writer.to_xml() |> MusicXML.Parser.parse()
      assert parsed == score
    end

    test "multi-voice measures survive write → parse" do
      score = %Score{
        parts: [
          %Part{
            instrument: :piano,
            name: "Piano",
            measures: [
              %Measure{
                number: 1,
                key: 0,
                time: {2, 4},
                clef: :treble,
                events: [
                  note(:C, 4, 1),
                  note(:E, 4, 1),
                  note(:G, 3, 2, {:half, 0})
                ]
              }
            ]
          }
        ]
      }

      assert {:ok, parsed} = score |> MusicXML.Writer.to_xml() |> MusicXML.Parser.parse()
      assert parsed == score
    end
  end

  property "any valid score survives write → parse" do
    check all score <- Generators.score() do
      assert {:ok, parsed} = score |> MusicXML.Writer.to_xml() |> MusicXML.Parser.parse()
      assert parsed == score
    end
  end
end
