defmodule Fermata.Interval do
  @moduledoc """
  A directed musical interval as a `{diatonic, chromatic}` pair —
  letter-steps and semitones, both signed, both counted from zero.

  Zero-based counting is deliberate: a "major third" is 2 diatonic steps
  and 4 semitones, not 3 and 4. It makes intervals add by plain addition,
  and it matches MusicXML's `<transpose>` element, whose `<diatonic>` and
  `<chromatic>` children are exactly these two numbers.

  Sign is direction: `major_second() |> negate()` is a major second down,
  which is what a Bb clarinet does to every note it reads.

      iex> Fermata.Interval.major_second() |> Fermata.Interval.negate()
      %Fermata.Interval{diatonic: -1, chromatic: -2}
  """

  defstruct diatonic: 0, chromatic: 0

  @type t :: %__MODULE__{diatonic: integer(), chromatic: integer()}

  def new(diatonic, chromatic), do: %__MODULE__{diatonic: diatonic, chromatic: chromatic}

  def unison, do: new(0, 0)
  def minor_second, do: new(1, 1)
  def major_second, do: new(1, 2)
  def minor_third, do: new(2, 3)
  def major_third, do: new(2, 4)
  def perfect_fourth, do: new(3, 5)
  def perfect_fifth, do: new(4, 7)
  def minor_sixth, do: new(5, 8)
  def major_sixth, do: new(5, 9)
  def minor_seventh, do: new(6, 10)
  def major_seventh, do: new(6, 11)
  def octave, do: new(7, 12)

  @doc "Reverse direction: up a fifth becomes down a fifth."
  def negate(%__MODULE__{} = i), do: %__MODULE__{diatonic: -i.diatonic, chromatic: -i.chromatic}

  @doc "Compose two intervals."
  def add(%__MODULE__{} = a, %__MODULE__{} = b),
    do: new(a.diatonic + b.diatonic, a.chromatic + b.chromatic)

  @doc "Add `n` octaves (negative to go down)."
  def plus_octaves(%__MODULE__{} = i, n), do: new(i.diatonic + 7 * n, i.chromatic + 12 * n)

  def unison?(%__MODULE__{diatonic: 0, chromatic: 0}), do: true
  def unison?(%__MODULE__{}), do: false

  @doc """
  How far this interval shifts a key signature, in fifths.

  Derived rather than tabulated: transpose a C and read the result's
  line-of-fifths position (see `Fermata.Pitch`). Down a major second
  gives -2, which is why concert C major is written as Bb major's
  signature for an instrument pitched a major second below.

      iex> Fermata.Interval.major_second() |> Fermata.Interval.negate()
      ...> |> Fermata.Interval.fifths_delta()
      -2
  """
  def fifths_delta(%__MODULE__{} = interval) do
    {step, alter, _octave} = Fermata.Pitch.transpose(:C, 0, 4, interval)
    Fermata.Pitch.fifths(step, alter)
  end

  @doc """
  The interval from one spelled pitch to another, octave included.
  """
  def between({s1, a1, o1}, {s2, a2, o2}) do
    alias Fermata.Pitch

    new(
      Pitch.step_index(s2) - Pitch.step_index(s1) + 7 * (o2 - o1),
      Pitch.chromatic(s2, a2, o2) - Pitch.chromatic(s1, a1, o1)
    )
  end

  @doc """
  Human-readable name, e.g. `"M2 down"`, `"P5 up"`, `"m3 + 1 octave down"`.
  Quality is inferred from the semitone/step relationship rather than
  stored, so unusual intervals still print something honest.
  """
  def to_string(%__MODULE__{diatonic: 0, chromatic: 0}), do: "unison"

  def to_string(%__MODULE__{} = i) do
    direction = if i.diatonic < 0 or i.chromatic < 0, do: "down", else: "up"
    %{diatonic: d, chromatic: c} = if direction == "down", do: negate(i), else: i

    octaves = div(d, 7)
    simple_d = rem(d, 7)
    simple_c = c - 12 * octaves

    label =
      case {quality(simple_d, simple_c), octaves} do
        # A whole number of octaves reads as octaves, not "P1 + 2 octaves"
        {"P1", 1} -> "1 octave"
        {"P1", n} -> "#{n} octaves"
        {base, 0} -> base
        {base, 1} -> "#{base} + 1 octave"
        {base, n} -> "#{base} + #{n} octaves"
      end

    "#{label} #{direction}"
  end

  @qualities %{
    {0, 0} => "P1",
    {0, 1} => "A1",
    {1, 1} => "m2",
    {1, 2} => "M2",
    {2, 3} => "m3",
    {2, 4} => "M3",
    {3, 5} => "P4",
    {3, 6} => "A4",
    {4, 6} => "d5",
    {4, 7} => "P5",
    {5, 8} => "m6",
    {5, 9} => "M6",
    {6, 10} => "m7",
    {6, 11} => "M7"
  }

  defp quality(d, c), do: Map.get(@qualities, {d, c}, "#{d}d/#{c}c")
end
