defmodule Tuist.MigrationVersionsTest do
  use ExUnit.Case, async: true

  for repo <- ["repo", "ingest_repo"] do
    test "#{repo} migration versions are unique" do
      migrations =
        :tuist
        |> Application.app_dir("priv/#{unquote(repo)}/migrations/*.exs")
        |> Path.wildcard()

      assert migrations != []

      duplicates =
        migrations
        |> Enum.group_by(fn path -> path |> Path.basename() |> String.split("_", parts: 2) |> hd() end)
        |> Enum.filter(fn {_version, paths} -> length(paths) > 1 end)

      assert duplicates == [], "Migration versions must be unique: #{inspect(duplicates)}"
    end
  end
end
