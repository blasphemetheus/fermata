defmodule Fermata.MusicXML.Writer do
  @moduledoc """
  Emits MusicXML 4.0 `score-partwise` from the score IR.

  Covers the Phase 0 subset: parts, measures, key/time/clef attributes,
  spelled notes with ties and chords, rests. Emission is direct iodata —
  the element set is small and fixed, so no XML builder dependency.
  """

  alias Fermata.{Duration, Instruments, Interval, Measure, Note, Part, Rest, Score}

  @doctype ~s(<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">)

  @spec to_xml(Score.t()) :: String.t()
  def to_xml(%Score{} = score) do
    IO.iodata_to_binary([
      ~s(<?xml version="1.0" encoding="UTF-8"?>\n),
      @doctype,
      "\n",
      ~s(<score-partwise version="4.0">\n),
      work(score),
      identification(score),
      part_list(score.parts),
      Enum.with_index(score.parts, 1) |> Enum.map(&part/1),
      "</score-partwise>\n"
    ])
  end

  defp work(%Score{title: nil}), do: []
  defp work(%Score{title: title}), do: ["<work><work-title>", escape(title), "</work-title></work>\n"]

  defp identification(%Score{composer: nil}), do: []

  defp identification(%Score{composer: composer}) do
    [
      ~s(<identification><creator type="composer">),
      escape(composer),
      "</creator></identification>\n"
    ]
  end

  defp part_list(parts) do
    [
      "<part-list>\n",
      parts
      |> Enum.with_index(1)
      |> Enum.map(fn {%Part{} = p, idx} ->
        name = p.name || Instruments.display_name(p.instrument)

        [
          ~s(<score-part id="P#{idx}"><part-name>),
          escape(name),
          "</part-name></score-part>\n"
        ]
      end),
      "</part-list>\n"
    ]
  end

  defp part({%Part{measures: measures} = p, idx}) do
    [
      ~s(<part id="P#{idx}">\n),
      measures
      |> Enum.with_index()
      # A transposing part declares <transpose> once, in its first
      # measure; without it a reader cannot know the written notes are
      # not the sounding ones.
      |> Enum.map(fn
        {m, 0} -> measure(m, p.transpose)
        {m, _} -> measure(m, nil)
      end),
      "</part>\n"
    ]
  end

  defp measure(%Measure{} = m, transpose) do
    [
      ~s(<measure number="#{m.number}">\n),
      attributes(m, transpose),
      voice_groups(m),
      "</measure>\n"
    ]
  end

  # MusicXML has no parallel notation: voices are written sequentially and
  # the cursor is rewound with <backup> between them. The rewind is the
  # preceding group's own duration, so voices need not be equal length.
  defp voice_groups(%Measure{} = m) do
    groups = Measure.voice_groups(m)
    # A lone voice needs no <voice> element at all; once there are two,
    # every note must be labelled or renderers guess at the split.
    explicit? = length(groups) > 1

    groups
    |> Enum.map_reduce(nil, fn {voice, events}, rewind ->
      label = if explicit?, do: voice, else: nil

      iodata = [
        if(rewind, do: "<backup><duration>#{rewind}</duration></backup>\n", else: []),
        Enum.map(events, &event(&1, label))
      ]

      {iodata, group_divisions(events)}
    end)
    |> elem(0)
  end

  # Chord members sound with the preceding note, so they consume no time.
  defp group_divisions(events) do
    events
    |> Enum.reject(&match?(%Note{chord: true}, &1))
    |> Enum.map(&Duration.divisions_for(&1.duration))
    |> Enum.sum()
  end

  defp attributes(%Measure{key: nil, time: nil, clef: nil}, nil), do: []

  defp attributes(%Measure{} = m, transpose) do
    [
      "<attributes>\n",
      # divisions must precede key/time/clef per the DTD content model;
      # emit it whenever any attribute is stated so measures stay
      # self-describing.
      "<divisions>#{Duration.divisions()}</divisions>\n",
      if(m.key, do: "<key><fifths>#{m.key}</fifths></key>\n", else: []),
      case m.time do
        nil -> []
        {beats, beat_type} -> "<time><beats>#{beats}</beats><beat-type>#{beat_type}</beat-type></time>\n"
      end,
      clef(m.clef),
      transpose_element(transpose),
      "</attributes>\n"
    ]
  end

  # <transpose> is written -> sounding, matching how the IR stores it.
  # Only whole octaves beyond the simple interval go in <octave-change>,
  # so a Bb clarinet emits the conventional diatonic -1 / chromatic -2
  # rather than an equivalent-but-odd 6/10/-1. Truncating division, not
  # floor: reduction has to move toward zero to keep the sign of the
  # simple interval, which is the direction the instrument transposes.
  defp transpose_element(nil), do: []

  defp transpose_element(%Interval{diatonic: d, chromatic: c}) do
    octaves = div(d, 7)

    [
      "<transpose>",
      "<diatonic>#{d - 7 * octaves}</diatonic>",
      "<chromatic>#{c - 12 * octaves}</chromatic>",
      if(octaves != 0, do: "<octave-change>#{octaves}</octave-change>", else: []),
      "</transpose>\n"
    ]
  end

  defp clef(nil), do: []
  defp clef(:treble), do: "<clef><sign>G</sign><line>2</line></clef>\n"
  defp clef(:bass), do: "<clef><sign>F</sign><line>4</line></clef>\n"
  defp clef(:alto), do: "<clef><sign>C</sign><line>3</line></clef>\n"
  defp clef(:tenor), do: "<clef><sign>C</sign><line>4</line></clef>\n"

  defp clef(:treble_8vb),
    do: "<clef><sign>G</sign><line>2</line><clef-octave-change>-1</clef-octave-change></clef>\n"

  # <voice> sits after <tie> and before <type> in the DTD content model.
  defp event(%Note{duration: {type, dots} = dur} = n, voice) do
    [
      "<note>",
      if(n.chord, do: "<chord/>", else: []),
      "<pitch><step>#{n.step}</step>",
      if(n.alter != 0, do: "<alter>#{n.alter}</alter>", else: []),
      "<octave>#{n.octave}</octave></pitch>",
      "<duration>#{Duration.divisions_for(dur)}</duration>",
      tie_elements(n.tie),
      voice_element(voice),
      "<type>#{type}</type>",
      List.duplicate("<dot/>", dots),
      tie_notations(n.tie),
      "</note>\n"
    ]
  end

  defp event(%Rest{duration: {type, dots} = dur}, voice) do
    [
      "<note><rest/>",
      "<duration>#{Duration.divisions_for(dur)}</duration>",
      voice_element(voice),
      "<type>#{type}</type>",
      List.duplicate("<dot/>", dots),
      "</note>\n"
    ]
  end

  defp voice_element(nil), do: []
  defp voice_element(voice), do: "<voice>#{voice}</voice>"

  # <tie> is the sounding tie (ordered before <type> in the DTD);
  # <notations><tied> is the engraved arc (ordered after <dot/>).
  # Both are needed for renderers to draw and play the tie.
  defp tie_elements(nil), do: []
  defp tie_elements(:start), do: ~s(<tie type="start"/>)
  defp tie_elements(:stop), do: ~s(<tie type="stop"/>)
  defp tie_elements(:both), do: ~s(<tie type="stop"/><tie type="start"/>)

  defp tie_notations(nil), do: []
  defp tie_notations(:start), do: ~s(<notations><tied type="start"/></notations>)
  defp tie_notations(:stop), do: ~s(<notations><tied type="stop"/></notations>)

  defp tie_notations(:both),
    do: ~s(<notations><tied type="stop"/><tied type="start"/></notations>)

  defp escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
