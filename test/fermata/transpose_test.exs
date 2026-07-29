defmodule Fermata.TransposeTest do
  use ExUnit.Case, async: true

  alias Fermata.{Instruments, Interval, Measure, Note, Part, Pitch, Rest, Score, Transpose}

  doctest Fermata.Interval
  doctest Fermata.Instruments

  defp note(step, alter, octave, dur \\ {:quarter, 0}),
    do: %Note{step: step, alter: alter, octave: octave, duration: dur}

  defp score(key, events) do
    %Score{
      parts: [
        %Part{
          instrument: :flute,
          name: "Flute",
          measures: [%Measure{number: 1, key: key, time: {4, 4}, clef: :treble, events: events}]
        }
      ]
    }
  end

  describe "spelled-pitch transposition" do
    test "preserves spelling rather than collapsing to pitch class" do
      # F# and Gb sound the same but are different notes; a minor third
      # up must keep them different (A vs Bbb).
      assert {:A, 0, 4} = Pitch.transpose(:F, 1, 4, Interval.minor_third())
      assert {:B, -2, 4} = Pitch.transpose(:G, -1, 4, Interval.minor_third())
    end

    test "carries the octave across the B/C boundary" do
      assert {:C, 0, 5} = Pitch.transpose(:B, 0, 4, Interval.minor_second())
      assert {:B, 0, 3} = Pitch.transpose(:C, 0, 4, Interval.minor_second() |> Interval.negate())
    end

    test "a Bb clarinet reading C sounds Bb a step lower" do
      interval = Instruments.transposition(:clarinet)
      assert {:B, -1, 3} = Pitch.transpose(:C, 0, 4, interval)
    end

    test "double accidentals survive" do
      assert {:F, 2, 4} = Pitch.transpose(:C, 2, 4, Interval.perfect_fourth())
    end
  end

  describe "line of fifths" do
    test "a major tonic's position is its key signature" do
      assert Pitch.fifths(:C, 0) == 0
      assert Pitch.fifths(:B, -1) == -2
      assert Pitch.fifths(:E, -1) == -3
      assert Pitch.fifths(:F, 1) == 6
    end

    test "round-trips through from_fifths/1" do
      for fifths <- -7..7 do
        {step, alter} = Pitch.from_fifths(fifths)
        assert Pitch.fifths(step, alter) == fifths
      end
    end
  end

  describe "key signatures" do
    test "move with the music" do
      down_major_second = Interval.negate(Interval.major_second())

      # C major down a major second is Bb major
      assert Transpose.transpose_key(0, down_major_second) == -2
      # G major (1 sharp) down a major second is F major (1 flat)
      assert Transpose.transpose_key(1, down_major_second) == -1
    end

    test "nil stays nil — an untitled measure gains no key" do
      assert Transpose.transpose_key(nil, Interval.major_third()) == nil
    end

    test "unwritable results are respelled enharmonically" do
      # B major (5 sharps) up a major second would be C# major (7#) —
      # writable. Up a further major second gives D# major (9#), which is
      # not, so it comes back as Eb major (3 flats).
      up = Interval.major_second()
      assert Transpose.transpose_key(5, up) == 7
      assert Transpose.transpose_key(7, up) == -3
    end
  end

  describe "to_written/2" do
    test "writes a Bb clarinet part a major second high with <transpose> set" do
      concert = score(0, [note(:C, 0, 4), note(:E, 0, 4)])

      [part] = Transpose.to_written(concert, :clarinet).parts

      assert part.instrument == :clarinet
      assert part.transpose == Instruments.transposition(:clarinet)

      [measure] = part.measures
      # Concert C major is written in D major (2 sharps)
      assert measure.key == 2
      assert [%Note{step: :D, alter: 0, octave: 4}, %Note{step: :F, alter: 1, octave: 4}] =
               measure.events
    end

    test "leaves concert-pitch instruments alone" do
      concert = score(0, [note(:C, 0, 4)])
      [part] = Transpose.to_written(concert, :cello).parts

      assert part.transpose == nil
      assert [%Measure{key: 0, events: [%Note{step: :C, octave: 4}]}] = part.measures
    end

    test "round-trips through to_concert/2" do
      concert = score(-2, [note(:B, -1, 3), note(:D, 0, 4), %Rest{duration: {:quarter, 0}}])

      for instrument <- [:clarinet, :alto_sax, :horn, :piccolo, :contrabass, :clarinet_ab] do
        back =
          concert
          |> Transpose.to_written(instrument)
          |> Transpose.to_concert(instrument)

        assert hd(back.parts).measures == hd(concert.parts).measures,
               "#{instrument} did not round-trip"
      end
    end

    test "rests are untouched but stay in place" do
      concert = score(0, [note(:C, 0, 4), %Rest{duration: {:half, 0}}])
      [part] = Transpose.to_written(concert, :clarinet).parts

      assert [%Note{step: :D}, %Rest{duration: {:half, 0}}] = hd(part.measures).events
    end
  end

  describe "to_key/3" do
    test "moves music into a target key by the nearest route" do
      concert = score(0, [note(:C, 0, 4), note(:G, 0, 4)])

      # C major -> Eb major (3 flats): nearest is a minor third up
      moved = Transpose.to_key(concert, -3)
      [measure] = hd(moved.parts).measures

      assert measure.key == -3
      assert [%Note{step: :E, alter: -1, octave: 4}, %Note{step: :B, alter: -1, octave: 4}] =
               measure.events
    end

    test "direction can be forced" do
      concert = score(0, [note(:C, 0, 4)])

      up = Transpose.to_key(concert, -3, direction: :up)
      down = Transpose.to_key(concert, -3, direction: :down)

      assert [%Note{step: :E, alter: -1, octave: 4}] = hd(hd(up.parts).measures).events
      # Downward lands on the same key a register lower
      assert [%Note{step: :E, alter: -1, octave: 3}] = hd(hd(down.parts).measures).events
    end

    test "raises when there is no key to transpose from" do
      keyless = score(nil, [note(:C, 0, 4)])

      assert_raise ArgumentError, fn -> Transpose.to_key(keyless, -3) end
    end
  end

  describe "range checks" do
    test "flags notes an instrument cannot play" do
      # C2 is far below a Bb clarinet's floor (sounding D3)
      too_low = score(0, [note(:C, 0, 2), note(:G, 0, 4)])

      assert [{1, %Note{step: :C, octave: 2}}] = Transpose.out_of_range(too_low, :clarinet)
      assert Transpose.out_of_range(too_low, :cello) == []
    end

    test "instruments without a catalogued range accept anything" do
      assert Instruments.sounding_range(:percussion) == nil
      assert Instruments.in_range?(:percussion, 0)
    end
  end

  describe "instrument registry" do
    test "resolves names, aliases and Humdrum codes" do
      assert Instruments.find("Cello") == {:ok, :cello}
      assert Instruments.find("cello") == {:ok, :cello}
      assert Instruments.find("Violoncello") == {:ok, :cello}
      assert Instruments.find("vlc") == {:ok, :cello}
      assert Instruments.find("violn") == {:ok, :violin}
      assert Instruments.find("clars") == {:ok, :clarinet}
      assert Instruments.find("cemba") == {:ok, :harpsichord}
    end

    test "ignores case, spacing and flat spelling" do
      assert Instruments.find("Bb Clarinet") == {:ok, :clarinet}
      assert Instruments.find("clarinet in B♭") == {:ok, :clarinet}
      assert Instruments.find("Eb Alto Sax") == {:ok, :alto_sax}
      assert Instruments.find("alto saxophone") == {:ok, :alto_sax}
    end

    test "an unqualified name is the common instrument" do
      # "Clarinet" means the Bb clarinet, not a keyed variant
      assert Instruments.transposition(:clarinet) ==
               Interval.negate(Interval.major_second())
    end

    test "unknown names fall back to :voice so ingestion continues" do
      assert Instruments.find("Ondes Martenot") == :error
      assert Instruments.from_name("Ondes Martenot") == :voice
    end

    test "every entry is internally consistent" do
      for id <- Instruments.all() do
        info = Instruments.info(id)
        assert is_binary(info.name)
        assert info.clef in Measure.clefs()
        assert info.family in Instruments.families()

        case info.range do
          nil -> :ok
          {low, high} -> assert low < high
        end
      end
    end
  end

  describe "vocabulary stability" do
    test "instruments added after Phase 0 do not shift frozen token ids" do
      ids = Fermata.Vocab.token_to_id()

      # Spot-check the boundaries of the frozen block: ids 0..526 are
      # baked into corpus shards on disk.
      assert ids[:bos] == 1
      assert ids[{:instrument, :soprano}] < ids[{:part, 0}]
      assert ids[{:dur, :"64th", 2}] == 526

      # Everything newer lives past the frozen block.
      assert ids[{:voice, 1}] > 526
      assert ids[{:instrument, :alto_sax}] > 526
    end

    test "Phase 0 and added instruments together are the whole roster" do
      assert Instruments.phase_0() ++ Instruments.added() == Instruments.all()
      assert length(Instruments.phase_0()) == 32
    end
  end
end
