defmodule Tuist.MigrationVersionsTest do
  use ExUnit.Case, async: true

  # Each repository records the versions it ran, so a second migration with a
  # version a database already recorded is skipped there without an error.
  for directory <- Path.wildcard(Path.expand("../../priv/*/migrations", __DIR__)) do
    @directory directory
    test "every migration in #{Path.relative_to(directory, Path.expand("../../priv", __DIR__))} has its own version" do
      duplicates =
        @directory
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".exs"))
        |> Enum.group_by(&(&1 |> String.split("_", parts: 2) |> hd()))
        |> Enum.filter(fn {_version, files} -> length(files) > 1 end)

      assert duplicates == []
    end
  end
end
