defmodule Fermata do
  @moduledoc """
  Fermata — a small language model for composing multi-part music, with
  engraved sheet-music output. See PLAN.md for the full design.

  This module is the convenience surface over the Phase 0 pipeline:

      score
      |> Fermata.to_tokens()      # IR → token ids (training data)
      |> Fermata.from_tokens()    # token ids → IR (model output)

      score
      |> Fermata.to_musicxml()    # IR → MusicXML string
      |> Fermata.render_pdf()     # MusicXML → PDF binary (needs verovio)
  """

  alias Fermata.{MusicXML, Render, Score, Tokenizer}

  @doc "Encode a score to integer token ids."
  def to_tokens(%Score{} = score), do: Tokenizer.encode_ids(score)

  @doc "Decode integer token ids back to a score."
  def from_tokens(ids) when is_list(ids), do: Tokenizer.decode_ids(ids)

  @doc "Serialize a score to a MusicXML 4.0 string."
  def to_musicxml(%Score{} = score), do: MusicXML.Writer.to_xml(score)

  @doc "Parse a MusicXML string into a score."
  def from_musicxml(xml) when is_binary(xml), do: MusicXML.Parser.parse(xml)

  @doc "Render MusicXML to a PDF binary (requires verovio + rsvg-convert)."
  def render_pdf(xml) when is_binary(xml), do: Render.to_pdf(xml)

  @doc "Render MusicXML to a list of SVG pages (requires verovio)."
  def render_svg(xml) when is_binary(xml), do: Render.to_svg(xml)
end
