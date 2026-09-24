defmodule Tuist.Repo.Migrations.MigrationVersionsTest do
  use ExUnit.Case, async: true

  test "migration versions are unique within each repository, including applied migrations" do
    for repo <- ["repo", "ingest_repo"] do
      duplicates =
        __DIR__
        |> Path.join("../../../../priv/#{repo}/migrations/*.exs")
        |> Path.wildcard()
        |> Enum.group_by(fn path ->
          path |> Path.basename() |> String.split("_", parts: 2) |> hd()
        end)
        |> Enum.filter(fn {_version, paths} -> length(paths) > 1 end)

      assert duplicates == [], "Duplicate #{repo} migration versions: #{inspect(duplicates)}"
    end
  end
end
