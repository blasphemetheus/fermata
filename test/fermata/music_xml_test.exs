defmodule Fermata.MusicXMLTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Fermata.{Fixtures.Chorale, Generators, MusicXML}

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

  describe "round-trip" do
    test "chorale fixture survives write → parse exactly" do
      score = Chorale.score()
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
