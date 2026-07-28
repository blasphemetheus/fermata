defmodule Fermata.Instruments do
  @moduledoc """
  The instrument roster: atom id ↔ display name ↔ default clef.

  This list is also the source of the tokenizer's instrument vocabulary,
  so ordering is significant — append only, never reorder, once training
  data exists.
  """

  @instruments [
    # {atom, display name, default clef}
    {:soprano, "Soprano", :treble},
    {:alto, "Alto", :treble},
    {:tenor, "Tenor", :treble_8vb},
    {:bass, "Bass", :bass},
    {:violin, "Violin", :treble},
    {:viola, "Viola", :alto},
    {:cello, "Violoncello", :bass},
    {:contrabass, "Contrabass", :bass},
    {:flute, "Flute", :treble},
    {:piccolo, "Piccolo", :treble},
    {:oboe, "Oboe", :treble},
    {:english_horn, "English Horn", :treble},
    {:clarinet, "Clarinet", :treble},
    {:bass_clarinet, "Bass Clarinet", :treble},
    {:bassoon, "Bassoon", :bass},
    {:contrabassoon, "Contrabassoon", :bass},
    {:horn, "Horn", :treble},
    {:trumpet, "Trumpet", :treble},
    {:trombone, "Trombone", :bass},
    {:bass_trombone, "Bass Trombone", :bass},
    {:tuba, "Tuba", :bass},
    {:timpani, "Timpani", :bass},
    {:harp, "Harp", :treble},
    {:piano, "Piano", :treble},
    {:organ, "Organ", :treble},
    {:harpsichord, "Harpsichord", :treble},
    {:guitar, "Guitar", :treble_8vb},
    {:recorder, "Recorder", :treble},
    {:voice, "Voice", :treble},
    {:mezzo_soprano, "Mezzo-soprano", :treble},
    {:baritone, "Baritone", :bass},
    {:percussion, "Percussion", :treble}
  ]

  @by_atom Map.new(@instruments, fn {atom, name, clef} -> {atom, {name, clef}} end)
  @by_name Map.new(@instruments, fn {atom, name, _clef} -> {name, atom} end)

  def all, do: Enum.map(@instruments, &elem(&1, 0))

  def display_name(instrument), do: @by_atom |> Map.fetch!(instrument) |> elem(0)

  def default_clef(instrument), do: @by_atom |> Map.fetch!(instrument) |> elem(1)

  @doc "Reverse lookup from a display name; falls back to `:voice` for unknown names."
  def from_name(name) when is_binary(name), do: Map.get(@by_name, name, :voice)

  def valid?(instrument), do: Map.has_key?(@by_atom, instrument)
end
