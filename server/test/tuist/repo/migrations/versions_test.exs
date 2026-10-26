defmodule Tuist.Repo.Migrations.VersionsTest do
  use ExUnit.Case, async: true

  test "publication migrations are present and PostgreSQL migration versions are unique" do
    files =
      :tuist
      |> Application.app_dir("priv/repo/migrations/*.exs")
      |> Path.wildcard()
      |> Enum.map(&Path.basename/1)

    assert "20261022104538_create_once_test_report_publications.exs" in files
    assert "20261022104539_index_once_test_report_publication_recovery.exs" in files

    duplicates =
      files
      |> Enum.flat_map(fn file ->
        case Regex.run(~r/^(\d+)_.*\.exs$/, file) do
          [_, version] -> [String.to_integer(version)]
          _ -> []
        end
      end)
      |> Enum.frequencies()
      |> Enum.filter(fn {_version, count} -> count > 1 end)

    assert duplicates == [], "duplicate PostgreSQL migration versions: #{inspect(duplicates)}"
  end
end
