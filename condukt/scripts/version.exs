defmodule Condukt.ReleaseVersion do
  @version_regex ~r/@version "(\d+)\.(\d+)\.(\d+)"/

  def main(["current"]) do
    mix_exs()
    |> current_version!()
    |> IO.puts()
  end

  def main(["bump", version, part]) do
    version
    |> parse_version!()
    |> bump(part)
    |> format_version()
    |> IO.puts()
  end

  def main(["set", version]) do
    path = "mix.exs"
    contents = File.read!(path)
    current = current_version!(contents)
    updated = Regex.replace(@version_regex, contents, ~s(@version "#{version}"), global: false)

    if current == version do
      IO.puts(version)
      System.halt(0)
    end

    if contents == updated do
      raise "Unable to update #{path} to #{version}"
    end

    File.write!(path, updated)
    IO.puts(version)
  end

  def main(_args) do
    IO.puts(:stderr, "usage: elixir scripts/version.exs [current|bump <version> <major|minor|patch>|set <version>]")
    System.halt(1)
  end

  defp mix_exs do
    File.read!("mix.exs")
  end

  defp current_version!(contents) do
    case Regex.run(@version_regex, contents, capture: :all_but_first) do
      [major, minor, patch] -> Enum.join([major, minor, patch], ".")
      _ -> raise "Unable to find @version in mix.exs"
    end
  end

  defp parse_version!(version) do
    case String.split(version, ".", parts: 3) do
      [major, minor, patch] ->
        {String.to_integer(major), String.to_integer(minor), String.to_integer(patch)}

      _ ->
        raise "Invalid version: #{version}"
    end
  end

  defp bump({major, _minor, _patch}, "major"), do: {major + 1, 0, 0}
  defp bump({major, minor, _patch}, "minor"), do: {major, minor + 1, 0}
  defp bump({major, minor, patch}, "patch"), do: {major, minor, patch + 1}
  defp bump(_version, part), do: raise("Unknown bump type: #{part}")

  defp format_version({major, minor, patch}), do: "#{major}.#{minor}.#{patch}"
end

Condukt.ReleaseVersion.main(System.argv())
