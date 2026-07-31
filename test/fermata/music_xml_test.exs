defmodule Fermata.MusicXMLTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Fermata.{Duration, Fixtures.Chorale, Generators, Instruments, Measure, MusicXML, Note,
                 Part, Rest, Score, Transpose}

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
      # The rewind is voice 1's two quarter notes
      assert xml =~ "<backup><duration>#{2 * Duration.divisions()}</duration></backup>"
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

  # Files in the wild (PDMX/MuseScore exports) interleave voices in
  # document order with <backup>/<forward> cursor moves, instead of
  # writing one voice group after another the way our writer does.
  describe "positioned input" do
    # 16 divisions per quarter; content plays inside one 4/4 measure.
    defp doc(measure_content) do
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <score-partwise version="4.0">
        <part-list>
          <score-part id="P1"><part-name>Piano</part-name></score-part>
        </part-list>
        <part id="P1">
          <measure number="1">
            <attributes><divisions>16</divisions></attributes>
            #{measure_content}
          </measure>
        </part>
      </score-partwise>
      """
    end

    defp n(step, oct, dur, type, voice) do
      """
      <note><pitch><step>#{step}</step><octave>#{oct}</octave></pitch>
      <duration>#{dur}</duration><voice>#{voice}</voice><type>#{type}</type></note>
      """
    end

    test "interleaved voices regroup into contiguous voice runs" do
      # v1 quarter, backup, v5 quarter, forward-free alternation
      xml =
        doc(
          n("C", 5, 16, "quarter", 1) <>
            "<backup><duration>16</duration></backup>" <>
            n("E", 3, 16, "quarter", 5) <>
            n("D", 5, 16, "quarter", 1) <>
            "<backup><duration>16</duration></backup>" <>
            n("F", 3, 16, "quarter", 5)
        )

      assert {:ok, %Score{parts: [%Part{measures: [m]}]}} = MusicXML.Parser.parse(xml)

      assert [{1, v1}, {2, v2}] = Measure.voice_groups(m)
      assert Enum.map(v1, & &1.step) == [:C, :D]
      assert Enum.map(v2, & &1.step) == [:E, :F]
      # sparse MuseScore voice numbers (1 and 5) renumber densely
      assert Enum.all?(v2, &(&1.voice == 2))
    end

    test "a forward gap inside a voice becomes explicit rests" do
      xml =
        doc(
          n("C", 5, 16, "quarter", 1) <>
            "<forward><duration>16</duration></forward>" <>
            n("D", 5, 16, "quarter", 1)
        )

      assert {:ok, %Score{parts: [%Part{measures: [m]}]}} = MusicXML.Parser.parse(xml)

      assert [%Note{step: :C}, %Rest{duration: {:quarter, 0}}, %Note{step: :D}] = m.events
    end

    test "a voice entering mid-measure is padded with leading rests" do
      xml =
        doc(
          n("C", 5, 32, "half", 1) <>
            "<backup><duration>16</duration></backup>" <>
            n("E", 3, 16, "quarter", 2)
        )

      assert {:ok, %Score{parts: [%Part{measures: [m]}]}} = MusicXML.Parser.parse(xml)

      assert [{1, [%Note{step: :C}]}, {2, [%Rest{duration: {:quarter, 0}}, %Note{step: :E}]}] =
               Measure.voice_groups(m)
    end

    test "grace notes are dropped" do
      grace =
        """
        <note><grace/><pitch><step>B</step><octave>4</octave></pitch>
        <voice>1</voice><type>eighth</type></note>
        """

      xml = doc(grace <> n("C", 5, 16, "quarter", 1))

      assert {:ok, %Score{parts: [%Part{measures: [m]}]}} = MusicXML.Parser.parse(xml)
      assert [%Note{step: :C}] = m.events
    end

    test "overlapping events in one voice are refused" do
      xml =
        doc(
          n("C", 5, 16, "quarter", 1) <>
            "<backup><duration>8</duration></backup>" <>
            n("D", 5, 16, "quarter", 1)
        )

      assert {:error, {{:overlapping_voice, 1}, {:measure, 1}}} = MusicXML.Parser.parse(xml)
    end

    test "a gap the divisions cannot express is refused" do
      # divisions=16 -> a 1-division forward is a 64th, fine; use
      # divisions=17 to force an inexpressible offset
      xml =
        String.replace(
          doc(
            n("C", 5, 17, "quarter", 1) <>
              "<forward><duration>5</duration></forward>" <>
              n("D", 5, 17, "quarter", 1)
          ),
          "<divisions>16</divisions>",
          "<divisions>17</divisions>"
        )

      assert {:error, {{:unrepresentable_offset, 5}, {:measure, 1}}} = MusicXML.Parser.parse(xml)
    end
  end
end
