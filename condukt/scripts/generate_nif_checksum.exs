# Generates a RustlerPrecompiled checksum file from prebuilt NIF artifact
# tarballs. Used by the release workflow after the NIF build matrix has
# produced one tarball per {target, NIF version} pair.
#
# Usage: elixir scripts/generate_nif_checksum.exs <artifacts_dir> <module_name>
#
# The generated file is consumed by `RustlerPrecompiled` at consumer
# compile time to verify that the downloaded NIF binary matches what we
# released.

case System.argv() do
  [artifacts_dir, module_name] ->
    if !File.dir?(artifacts_dir) do
      IO.puts(:stderr, "artifacts directory not found: #{artifacts_dir}")
      System.halt(1)
    end

    output_file = "checksum-#{module_name}.exs"

    entries =
      artifacts_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".tar.gz"))
      |> Enum.sort()
      |> Enum.map(fn name ->
        path = Path.join(artifacts_dir, name)
        sha = :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)
        {name, "sha256:" <> sha}
      end)

    if entries == [] do
      IO.puts(:stderr, "no .tar.gz artifacts found in #{artifacts_dir}")
      System.halt(1)
    end

    content =
      "%{\n" <>
        Enum.map_join(entries, ",\n", fn {name, hash} -> "  #{inspect(name)} => #{inspect(hash)}" end) <>
        "\n}\n"

    File.write!(output_file, content)

    IO.puts("wrote #{length(entries)} checksums to #{output_file}")

  _ ->
    IO.puts(:stderr, "usage: elixir scripts/generate_nif_checksum.exs <artifacts_dir> <module_name>")
    System.halt(1)
end
