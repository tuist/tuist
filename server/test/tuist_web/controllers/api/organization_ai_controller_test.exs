defmodule TuistWeb.API.OrganizationAIControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.OrganizationAIConnection
  alias Tuist.FeatureFlags
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup %{conn: conn} do
    admin = AccountsFixtures.user_fixture(preload: [:account])
    organization = AccountsFixtures.organization_fixture(creator: admin, preload: [:account])
    account = organization.account
    stub(FeatureFlags, :organization_luft_enabled?, fn actor -> actor.id == account.id end)

    conn =
      conn
      |> assign(:current_user, admin)
      |> put_req_header("content-type", "application/json")

    %{conn: conn, admin: admin, organization: organization, account: account, path: "/api/accounts/#{account.name}/ai"}
  end

  test "an admin configures providers, models, the default and task routes", %{conn: conn, path: path} do
    assert %{"providers" => [], "models" => [], "default_model_id" => nil, "task_routes" => [], "tasks" => tasks} =
             conn |> get(path) |> json_response(:ok)

    assert Enum.map(tasks, &{&1["task"], &1["source"]}) == [{"pulse_grouping", "none"}, {"pulse_explanation", "none"}]

    response =
      conn
      |> post("#{path}/providers", %{name: "Together AI", base_url: "https://api.together.ai/v1", api_key: "secret-key"})
      |> response(:ok)

    refute response =~ "secret-key"
    assert %{"providers" => [%{"id" => provider_id, "kind" => "api_key"} = provider]} = JSON.decode!(response)
    refute Map.has_key?(provider, "api_key")

    conn |> patch("#{path}/providers/#{provider_id}", %{name: "Together"}) |> json_response(:ok)
    assert Repo.get!(OrganizationAIConnection, provider_id).api_key == "secret-key"

    %{"models" => [%{"id" => tev1, "upstream_model_id" => "together/Tev1-4B-experimental"}]} =
      conn
      |> post("#{path}/models", %{
        name: "Tev1",
        provider_id: provider_id,
        upstream_model_id: "together/Tev1-4B-experimental"
      })
      |> json_response(:ok)

    %{"models" => [_, %{"id" => oss}]} =
      conn
      |> post("#{path}/models", %{name: "GPT-OSS", provider_id: provider_id, upstream_model_id: "openai/gpt-oss-120b"})
      |> json_response(:ok)

    %{"task_routes" => [%{"id" => route_id}]} =
      conn |> post("#{path}/task-routes", %{task: "pulse_grouping", model_id: tev1}) |> json_response(:ok)

    assert %{"message" => _} =
             conn
             |> post("#{path}/task-routes", %{task: "pulse_grouping", model_id: oss})
             |> json_response(:unprocessable_entity)

    assert conn |> post("#{path}/task-routes", %{task: "unknown", model_id: oss}) |> response(400)

    assert %{"default_model_id" => ^oss, "tasks" => tasks} =
             conn |> put("#{path}/default-model", %{model_id: oss}) |> json_response(:ok)

    assert tasks == [
             %{"task" => "pulse_grouping", "category" => "pulse", "model_id" => tev1, "source" => "route"},
             %{"task" => "pulse_explanation", "category" => "pulse", "model_id" => oss, "source" => "default"}
           ]

    assert %{"task_routes" => [%{"model_id" => ^oss}]} =
             conn |> patch("#{path}/task-routes/#{route_id}", %{model_id: oss}) |> json_response(:ok)

    assert %{"models" => [%{"name" => "Tev1 4B"}, _]} =
             conn |> patch("#{path}/models/#{tev1}", %{name: "Tev1 4B"}) |> json_response(:ok)

    assert %{"task_routes" => []} = conn |> delete("#{path}/task-routes/#{route_id}") |> json_response(:ok)
    assert %{"default_model_id" => nil} = conn |> put("#{path}/default-model", %{model_id: nil}) |> json_response(:ok)
    assert %{"models" => [%{"id" => ^oss}]} = conn |> delete("#{path}/models/#{tev1}") |> json_response(:ok)

    assert %{"providers" => [], "models" => []} =
             conn |> delete("#{path}/providers/#{provider_id}") |> json_response(:ok)
  end

  test "refuses members, account tokens, other organizations' records and disabled organizations", %{
    conn: conn,
    admin: admin,
    organization: organization,
    account: account,
    path: path
  } do
    member = AccountsFixtures.user_fixture(preload: [:account])
    Accounts.add_user_to_organization(member, organization, role: :user)
    assert conn |> assign(:current_user, member) |> get(path) |> json_response(:forbidden)

    token_conn =
      build_conn()
      |> assign(:current_subject, %AuthenticatedAccount{account: account, scopes: ["account:registry:read"]})
      |> put_req_header("content-type", "application/json")

    assert token_conn |> get(path) |> json_response(:forbidden)

    other_admin = AccountsFixtures.user_fixture(preload: [:account])
    other = AccountsFixtures.organization_fixture(creator: other_admin, preload: [:account]).account
    stub(FeatureFlags, :organization_luft_enabled?, fn _ -> true end)

    %{"providers" => [%{"id" => provider_id}]} =
      conn
      |> post("#{path}/providers", %{name: "Ours", base_url: "https://api.together.ai/v1", api_key: "key"})
      |> json_response(:ok)

    other_conn = assign(conn, :current_user, other_admin)

    assert other_conn
           |> post("/api/accounts/#{other.name}/ai/models", %{
             name: "Foreign",
             provider_id: provider_id,
             upstream_model_id: "example"
           })
           |> json_response(:unprocessable_entity)

    assert other_conn |> delete("/api/accounts/#{other.name}/ai/providers/#{provider_id}") |> json_response(:not_found)
    assert Repo.get(OrganizationAIConnection, provider_id)

    stub(FeatureFlags, :organization_luft_enabled?, fn _ -> false end)
    assert conn |> get(path) |> json_response(:not_found)
    assert admin.account.id != account.id
  end
end
