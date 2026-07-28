defmodule Fermata.Fixtures.Chorale do
  @moduledoc """
  A hand-written SATB chorale phrase (two measures plus a final chord,
  C major, 4/4) used as the canonical multi-part fixture. Simple diatonic
  voice-leading ending on an authentic cadence.
  """

  alias Fermata.{Measure, Note, Part, Rest, Score}

  def score do
    %Score{
      title: "Chorale Fixture",
      composer: "Fermata",
      parts: [
        %Part{instrument: :soprano, name: "Soprano", measures: soprano()},
        %Part{instrument: :alto, name: "Alto", measures: alto()},
        %Part{instrument: :tenor, name: "Tenor", measures: tenor()},
        %Part{instrument: :bass, name: "Bass", measures: bass()}
      ]
    }
  end

  defp q(step, octave, alter \\ 0), do: %Note{step: step, octave: octave, alter: alter, duration: {:quarter, 0}}
  defp h(step, octave), do: %Note{step: step, octave: octave, duration: {:half, 0}}

  defp soprano do
    [
      %Measure{
        number: 1,
        key: 0,
        time: {4, 4},
        clef: :treble,
        events: [q(:E, 5), q(:E, 5), q(:F, 5), q(:G, 5)]
      },
      %Measure{
        number: 2,
        events: [q(:G, 5), q(:F, 5), q(:E, 5), q(:D, 5)]
      },
      %Measure{
        number: 3,
        events: [%Note{step: :C, octave: 5, duration: {:half, 1}}, %Rest{duration: {:quarter, 0}}]
      }
    ]
  end

  defp alto do
    [
      %Measure{
        number: 1,
        key: 0,
        time: {4, 4},
        clef: :treble,
        events: [q(:C, 5), q(:C, 5), q(:D, 5), q(:D, 5)]
      },
      %Measure{
        number: 2,
        events: [q(:E, 5), q(:D, 5), q(:C, 5), %Note{step: :B, octave: 4, duration: {:quarter, 0}, tie: :start}]
      },
      %Measure{
        number: 3,
        events: [
          %Note{step: :B, octave: 4, duration: {:quarter, 0}, tie: :stop},
          q(:C, 5),
          h(:C, 5)
        ]
      }
    ]
  end

  defp tenor do
    [
      %Measure{
        number: 1,
        key: 0,
        time: {4, 4},
        clef: :treble_8vb,
        events: [q(:G, 4), q(:G, 4), q(:A, 4), q(:B, 4)]
      },
      %Measure{
        number: 2,
        events: [q(:C, 5), q(:A, 4), q(:G, 4), q(:G, 4)]
      },
      %Measure{
        number: 3,
        events: [q(:G, 4), q(:F, 4), h(:E, 4)]
      }
    ]
  end

  defp bass do
    [
      %Measure{
        number: 1,
        key: 0,
        time: {4, 4},
        clef: :bass,
        events: [q(:C, 3), q(:C, 3), q(:D, 3), q(:G, 3)]
      },
      %Measure{
        number: 2,
        events: [q(:C, 3), q(:D, 3), q(:E, 3), q(:G, 2)]
      },
      %Measure{
        number: 3,
        events: [q(:G, 2), q(:G, 2), h(:C, 3)]
      }
    ]
  end
end
