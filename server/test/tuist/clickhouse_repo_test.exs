defmodule Tuist.ClickHouseRepoTest do
  use ExUnit.Case, async: false

  alias Tuist.ClickHouseRepo

  test "query settings override the connection defaults" do
    with_read_repo(fn ->
      assert resource_settings() == %{
               "max_memory_usage" => "6442450944",
               "max_threads" => "4"
             }

      assert resource_settings(
               settings: [
                 max_threads: 2,
                 max_memory_usage: 1024 * 1024 * 1024
               ]
             ) == %{
               "max_memory_usage" => "1073741824",
               "max_threads" => "2"
             }
    end)
  end

  defp resource_settings(options \\ []) do
    %{rows: rows} =
      ClickHouseRepo.query!(
        """
        SELECT name, value
        FROM system.settings
        WHERE name IN ('max_threads', 'max_memory_usage')
        """,
        %{},
        options
      )

    Map.new(rows, fn [name, value] -> {name, value} end)
  end

  defp with_read_repo(fun) do
    previous_dynamic_repo = ClickHouseRepo.get_dynamic_repo()

    try do
      ClickHouseRepo.put_dynamic_repo(ClickHouseRepo)
      fun.()
    after
      ClickHouseRepo.put_dynamic_repo(previous_dynamic_repo)
    end
  end
end
