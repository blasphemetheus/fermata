defmodule Fermata.Pitch do
  @moduledoc """
  Arithmetic on **spelled** pitches (`step` + `alter` + `octave`).

  Two coordinate systems are used, and the distinction is the whole point:

    * **chromatic** — semitones, MIDI numbering (C4 = 60). Says how high a
      pitch sounds. Loses spelling: F#4 and Gb4 are both 66.
    * **line of fifths** — `base(step) + 7 * alter`, where base is
      C=0 G=1 D=2 A=3 E=4 B=5 F=-1. Says how a pitch is *spelled*,
      ignoring octave. F#=6, Gb=-6 — distinct, as they must be.

  The line of fifths is not a curiosity: a major key's position on it is
  exactly its MusicXML `<fifths>` number, so transposing a key signature
  is the same operation as transposing a pitch (see `Fermata.Transpose`).
  """

  alias Fermata.{Interval, Note}

  @steps [:C, :D, :E, :F, :G, :A, :B]
  @naturals %{C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11}
  @fifths %{C: 0, G: 1, D: 2, A: 3, E: 4, B: 5, F: -1}

  @doc "Semitone offset of the natural step within its octave (C = 0)."
  def natural(step), do: Map.fetch!(@naturals, step)

  @doc "0-based index of the step in C..B order."
  def step_index(step), do: Enum.find_index(@steps, &(&1 == step))

  @doc "Step at a 0-based index, wrapping (so 7 is C again)."
  def step_at(index), do: Enum.at(@steps, Integer.mod(index, 7))

  @doc "MIDI note number (C4 = 60)."
  def chromatic(step, alter, octave), do: 12 * (octave + 1) + natural(step) + alter

  def chromatic(%Note{} = n), do: chromatic(n.step, n.alter, n.octave)

  @doc """
  Position on the line of fifths — the spelling coordinate, octave-free.
  For a major tonic this is the key signature's `<fifths>` value.
  """
  def fifths(step, alter), do: Map.fetch!(@fifths, step) + 7 * alter

  def fifths(%Note{} = n), do: fifths(n.step, n.alter)

  @doc """
  The spelled pitch at a given line-of-fifths position, in the octave
  containing the equivalent of C4 — the inverse of `fifths/2`, used to
  recover a key's tonic from its `<fifths>` count.
  """
  def from_fifths(position) do
    step = step_at(Integer.mod(position * 4, 7))
    alter = div(position - Map.fetch!(@fifths, step), 7)
    {step, alter}
  end

  @doc """
  Transpose a spelled pitch by an interval, preserving spelling.

  The letter moves by the interval's diatonic count, then the accidental
  is whatever makes the result land on the right semitone. This is why
  transposing C up an augmented unison gives C#, not Db.
  """
  def transpose(step, alter, octave, %Interval{diatonic: d, chromatic: c}) do
    index = step_index(step) + d
    new_step = step_at(index)
    new_octave = octave + Integer.floor_div(index, 7)
    target = chromatic(step, alter, octave) + c
    new_alter = target - (12 * (new_octave + 1) + natural(new_step))

    {new_step, new_alter, new_octave}
  end

  @doc "Transpose a `Fermata.Note`, leaving everything but the pitch alone."
  def transpose(%Note{} = n, %Interval{} = interval) do
    {step, alter, octave} = transpose(n.step, n.alter, n.octave, interval)
    %{n | step: step, alter: alter, octave: octave}
  end

  def steps, do: @steps
end
