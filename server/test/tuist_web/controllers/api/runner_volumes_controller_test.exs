defmodule TuistWeb.API.RunnerVolumesControllerTest do
  use ExUnit.Case, async: true
  use Mimic

  import Plug.Conn

  alias OpenApiSpex.Plug.PutApiSpec
  alias Tuist.Accounts
  alias Tuist.Authorization
  alias Tuist.FeatureFlags
  alias Tuist.Runners.CacheVolumes.Query
  alias TuistWeb.API.RunnerVolumesController, as: Controller

  setup do
    account = %{id: 1, name: "acme"}
    stub(Accounts, :get_account_by_handle, fn "acme" -> account end)
    stub(FeatureFlags, :runners_enabled?, fn ^account -> true end)
    %{account: account, id: Ecto.UUID.generate()}
  end

  defp call(action, params \\ %{}) do
    method = if action == :clear, do: :post, else: :get
    path = Map.merge(%{"account_handle" => "acme"}, Map.take(params, ["volume_id", "workflow_job_id"]))
    query = Map.drop(params, ["volume_id", "workflow_job_id"])
    conn = Plug.Test.conn(method, "/?" <> URI.encode_query(query))
    conn = %{conn | path_params: path, params: Map.merge(path, query), query_params: query, body_params: %{}}

    conn
    |> assign(:current_subject, :subject)
    |> PutApiSpec.call(PutApiSpec.init(module: TuistWeb.API.Spec))
    |> Controller.call(action)
  end

  test "casts pagination and dispatches authorized reads through the shared query", %{account: account} do
    expect(Authorization, :authorize, fn :runners_read, :subject, ^account -> :ok end)

    expect(Query, :run, fn :list, 1, args ->
      assert args["page"] == 2
      assert args["page_size"] == 3
      {:ok, %{volumes: []}}
    end)

    result = call(:list, %{"page" => "2", "page_size" => "3"})
    assert result.status == 200
    assert get_resp_header(result, "cache-control") == ["private, no-store"]
  end

  test "invalid pagination is rejected before storage access" do
    reject(&Query.run/3)
    assert call(:list, %{"page_size" => "101"}).status == 400
  end

  test "clearing uses administrative authorization and returns the shared result", %{account: account, id: id} do
    expect(Authorization, :authorize, fn :account_update, :subject, ^account -> :ok end)

    expect(Query, :run, fn :clear, 1, %{"account_handle" => "acme", "volume_id" => ^id} ->
      {:ok, %{id: id, cleared: true}}
    end)

    result = call(:clear, %{"volume_id" => id})
    assert result.status == 200
    assert JSON.decode!(result.resp_body) == %{"id" => id, "cleared" => true}
  end

  test "readers cannot clear and denial never reaches storage", %{account: account, id: id} do
    expect(Authorization, :authorize, fn :account_update, :subject, ^account -> {:error, :forbidden} end)
    stub(TuistWeb.RateLimit.Authorization, :hit, fn _ -> {:allow, 1} end)
    reject(&Query.run/3)
    assert call(:clear, %{"volume_id" => id}).status == 403
  end

  test "disabled accounts cannot query volumes", %{account: account} do
    expect(Authorization, :authorize, fn :runners_read, :subject, ^account -> :ok end)
    stub(FeatureFlags, :runners_enabled?, fn ^account -> false end)
    reject(&Query.run/3)
    assert call(:list).status == 404
  end

  test "missing or cross-account volume maps to 404", %{account: account, id: id} do
    expect(Authorization, :authorize, fn :runners_read, :subject, ^account -> :ok end)
    expect(Query, :run, fn :show, 1, _ -> {:error, :not_found} end)
    assert call(:show, %{"volume_id" => id}).status == 404
  end
end
