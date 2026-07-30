# Convert a tree of MuseScore .mscx files to MusicXML with headless
# MuseScore, in one batch job. Not part of the render pipeline — this is
# one-time corpus prep for the OpenScore sources (CLAUDE.md's "avoid
# MuseScore headless" applies to rendering, not to this).
#
#   nix shell nixpkgs#musescore nixpkgs#xvfb-run --command \
#     mix run scripts/convert_mscx.exs data/raw/openscore_lieder
#
# Reads  <root>/scores/**/*.mscx
# Writes <root>/musicxml/<basename>.musicxml (basenames are unique in
# both OpenScore corpora) plus a mscore-job.json driving the batch.

[root] = System.argv()
out_dir = Path.join(root, "musicxml")
File.mkdir_p!(out_dir)

jobs =
  Path.wildcard(Path.join(root, "scores/**/*.mscx"))
  |> Enum.sort()
  |> Enum.map(fn mscx ->
    out = Path.join(out_dir, Path.basename(mscx, ".mscx") <> ".musicxml")
    %{"in" => mscx, "out" => out}
  end)
  |> Enum.reject(&File.exists?(&1["out"]))

job_path = Path.join(root, "mscore-job.json")

encode = fn %{"in" => i, "out" => o} ->
  ~s({"in": #{inspect(i)}, "out": #{inspect(o)}})
end

File.write!(job_path, "[\n" <> Enum.map_join(jobs, ",\n", encode) <> "\n]\n")
IO.puts("#{length(jobs)} conversions queued in #{job_path}")

if jobs != [] do
  {out, code} =
    System.cmd("xvfb-run", ["-a", "mscore", "-j", job_path], stderr_to_stdout: true)

  done = Path.wildcard(Path.join(out_dir, "*.musicxml")) |> length()
  IO.puts("mscore exited #{code}; #{done} MusicXML files present")
  if code != 0, do: IO.puts(String.slice(out, -2000, 2000))
end
