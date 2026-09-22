defmodule Tuist.MCP.Components.Tools.RunnerVolumeToolsTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Authorization
  alias Tuist.FeatureFlags
  alias Tuist.MCP.Components.Tools.ClearRunnerVolume
  alias Tuist.MCP.Components.Tools.GetRunnerVolume
  alias Tuist.MCP.Components.Tools.ListRunnerJobVolumes
  alias Tuist.MCP.Components.Tools.ListRunnerVolumes
  alias Tuist.Runners.CacheVolumes
  alias Tuist.Runners.CacheVolumes.Query
  alias Tuist.Runners.CacheVolumes.Usage
  alias Tuist.Runners.CacheVolumes.Volume
  alias Tuist.Runners.Jobs

  setup do
    account = %{id: 1, name: "acme"}
    stub(Accounts, :get_account_by_handle, fn "acme" -> account end)
    stub(FeatureFlags, :runners_enabled?, fn ^account -> true end)
    %{account: account, conn: %Plug.Conn{assigns: %{current_subject: :subject}}, id: Ecto.UUID.generate()}
  end

  test "read tools authorize and return the shared paginated contract", %{account: account, conn: conn} do
    expect(Authorization, :authorize, fn :runners_read, :subject, ^account -> :ok end)

    expect(Query, :run, fn :list, 1, %{"account_handle" => "acme", "page_size" => 1} ->
      {:ok,
       %{
         volumes: [],
         pagination_metadata: %{
           has_next_page: false,
           has_previous_page: false,
           current_page: 1,
           page_size: 1,
           total_count: 0,
           total_pages: 0
         }
       }}
    end)

    assert %{"structuredContent" => %{"volumes" => [], "pagination_metadata" => %{"page_size" => 1}}} =
             ListRunnerVolumes.call(conn, %{"account_handle" => "acme", "page_size" => 1})
  end

  test "job references bind account, run and job and retain unknown metrics", %{account: account, conn: conn, id: id} do
    expect(Authorization, :authorize, fn :runners_read, :subject, ^account -> :ok end)
    expect(Jobs, :get_for_account, fn 1, 42 -> {:ok, %{workflow_run_id: 7, workflow_job_id: 42}} end)

    expect(CacheVolumes, :for_job, fn 1, 7, 42 ->
      [
        %Usage{
          id: Ecto.UUID.generate(),
          volume_id: id,
          workflow_run_id: 7,
          workflow_job_id: 42,
          status: "attached",
          warm: nil,
          volume: %Volume{id: id, key: "gradle", repository: "acme/app", provider: "github", architecture: "amd64"}
        }
      ]
    end)

    expect(CacheVolumes, :statistics, fn [^id] -> %{} end)

    assert %{
             "structuredContent" => %{
               "volumes" => [%{"volume" => %{"capacity_bytes" => nil}, "usage" => %{"cache_hit" => nil}}]
             }
           } = ListRunnerJobVolumes.call(conn, %{"account_handle" => "acme", "workflow_job_id" => 42})
  end

  test "unknown or foreign jobs do not query mounted volumes", %{account: account, conn: conn} do
    expect(Authorization, :authorize, fn :runners_read, :subject, ^account -> :ok end)
    expect(Jobs, :get_for_account, fn 1, 42 -> {:error, :not_found} end)
    reject(&CacheVolumes.for_job/3)
    assert %{"isError" => true} = ListRunnerJobVolumes.call(conn, %{"account_handle" => "acme", "workflow_job_id" => 42})
  end

  test "clear requires account administration and is declared destructive", %{account: account, conn: conn, id: id} do
    expect(Authorization, :authorize, fn :account_update, :subject, ^account -> :ok end)

    expect(Query, :run, fn :clear, 1, %{"account_handle" => "acme", "volume_id" => ^id} ->
      {:ok, %{id: id, cleared: true}}
    end)

    assert %{"structuredContent" => %{"cleared" => true}} =
             ClearRunnerVolume.call(conn, %{"account_handle" => "acme", "volume_id" => id})

    assert %{readOnlyHint: false, destructiveHint: true} = ClearRunnerVolume.annotations()
  end

  test "read access does not grant clearing", %{account: account, conn: conn, id: id} do
    expect(Authorization, :authorize, fn :account_update, :subject, ^account -> {:error, :forbidden} end)
    reject(&Query.run/3)
    assert %{"isError" => true} = ClearRunnerVolume.call(conn, %{"account_handle" => "acme", "volume_id" => id})
  end

  test "disabled accounts cannot query volumes", %{account: account, conn: conn, id: id} do
    expect(Authorization, :authorize, fn :runners_read, :subject, ^account -> :ok end)
    stub(FeatureFlags, :runners_enabled?, fn ^account -> false end)
    reject(&Query.run/3)
    assert %{"isError" => true} = GetRunnerVolume.call(conn, %{"account_handle" => "acme", "volume_id" => id})
  end

  test "invalid pagination is rejected before authorization", %{conn: conn} do
    reject(&Authorization.authorize/3)
    reject(&Query.run/3)
    assert %{"isError" => true} = ListRunnerVolumes.call(conn, %{"account_handle" => "acme", "page_size" => 101})
  end
end
