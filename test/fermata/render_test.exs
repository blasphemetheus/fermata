defmodule Fermata.RenderTest do
  use ExUnit.Case, async: true

  alias Fermata.{Fixtures.Chorale, MusicXML, Render}

  test "available/0 reports renderer presence as booleans" do
    availability = Render.available()

    assert is_map(availability)
    assert Map.keys(availability) |> Enum.sort() == [:lilypond, :"rsvg-convert", :verovio]
    assert Enum.all?(Map.values(availability), &is_boolean/1)
  end

  test "renders the chorale to SVG, or fails cleanly when verovio is absent" do
    xml = MusicXML.Writer.to_xml(Chorale.score())

    case Render.to_svg(xml) do
      {:ok, pages} ->
        assert [svg | _] = pages
        assert svg =~ "<svg"

      {:error, {:renderer_not_found, :verovio}} ->
        :ok
    end
  end
end
