defmodule Tuist.MCP.Components.Tools.OrganizationAIToolsTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.OrganizationAI
  alias Tuist.FeatureFlags
  alias Tuist.MCP.Components.Tools.GetOrganizationAIConfiguration
  alias Tuist.MCP.Components.Tools.RemoveOrganizationAIModel
  alias Tuist.MCP.Components.Tools.RemoveOrganizationAIProvider
  alias Tuist.MCP.Components.Tools.RemoveOrganizationAITaskRoute
  alias Tuist.MCP.Components.Tools.SaveOrganizationAIModel
  alias Tuist.MCP.Components.Tools.SaveOrganizationAITaskRoute
  alias Tuist.MCP.Components.Tools.SetOrganizationAIDefaultModel
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    admin = AccountsFixtures.user_fixture(preload: [:account])
    organization = AccountsFixtures.organization_fixture(creator: admin, preload: [:account])
    account = organization.account
    stub(FeatureFlags, :organization_luft_enabled?, fn actor -> actor.id == account.id end)

    {:ok, provider} =
      OrganizationAI.save_connection(admin, account, %{
        "name" => "Together AI",
        "base_url" => "https://api.together.ai/v1",
        "api_key" => "private-key"
      })

    %{admin: admin, organization: organization, account: account, handle: account.name, provider: provider}
  end

  defp user_conn(user), do: %Plug.Conn{assigns: %{current_user: user}}

  test "an admin manages models, the default and task routes", %{admin: admin, handle: handle, provider: provider} do
    conn = user_conn(admin)

    added =
      SaveOrganizationAIModel.call(conn, %{
        "account_handle" => handle,
        "name" => "Tev1",
        "provider_id" => provider.id,
        "upstream_model_id" => "together/Tev1-4B-experimental"
      })

    refute added["isError"]
    assert [%{"id" => tev1, "provider_id" => provider_id}] = added["structuredContent"]["models"]
    assert provider_id == provider.id

    %{"structuredContent" => %{"models" => [_, %{"id" => oss}]}} =
      SaveOrganizationAIModel.call(conn, %{
        "account_handle" => handle,
        "name" => "GPT-OSS",
        "provider_id" => provider.id,
        "upstream_model_id" => "openai/gpt-oss-120b"
      })

    routed =
      SaveOrganizationAITaskRoute.call(conn, %{"account_handle" => handle, "task" => "pulse_grouping", "model_id" => tev1})

    assert %{"task_routes" => [%{"id" => route_id, "task" => "pulse_grouping"}], "tasks" => tasks} =
             routed["structuredContent"]

    assert tasks == [
             %{"task" => "pulse_grouping", "category" => "pulse", "model_id" => tev1, "source" => "route"},
             %{"task" => "pulse_explanation", "category" => "pulse", "model_id" => nil, "source" => "none"}
           ]

    duplicate =
      SaveOrganizationAITaskRoute.call(conn, %{"account_handle" => handle, "task" => "pulse_grouping", "model_id" => oss})

    assert duplicate["isError"]

    defaulted = SetOrganizationAIDefaultModel.call(conn, %{"account_handle" => handle, "model_id" => oss})

    assert %{"default_model_id" => ^oss, "tasks" => [_, %{"model_id" => ^oss, "source" => "default"}]} =
             defaulted["structuredContent"]

    renamed = SaveOrganizationAIModel.call(conn, %{"account_handle" => handle, "id" => tev1, "name" => "Tev1 4B"})

    assert %{"name" => "Tev1 4B", "upstream_model_id" => "together/Tev1-4B-experimental"} =
             hd(renamed["structuredContent"]["models"])

    edited = SaveOrganizationAITaskRoute.call(conn, %{"account_handle" => handle, "id" => route_id, "model_id" => oss})
    assert [%{"model_id" => ^oss}] = edited["structuredContent"]["task_routes"]

    removed = RemoveOrganizationAITaskRoute.call(conn, %{"account_handle" => handle, "route_id" => route_id})
    assert %{"task_routes" => [], "tasks" => [%{"source" => "default"}, _]} = removed["structuredContent"]

    cleared = SetOrganizationAIDefaultModel.call(conn, %{"account_handle" => handle, "model_id" => nil})
    assert %{"default_model_id" => nil} = cleared["structuredContent"]

    assert %{"models" => [%{"id" => ^oss}]} =
             RemoveOrganizationAIModel.call(conn, %{"account_handle" => handle, "model_id" => tev1})["structuredContent"]

    read = GetOrganizationAIConfiguration.call(conn, %{"account_handle" => handle})
    assert [%{"kind" => "api_key", "name" => "Together AI"} = returned_provider] = read["structuredContent"]["providers"]
    refute Map.has_key?(returned_provider, "api_key")
    refute inspect(read) =~ "private-key"

    assert %{"providers" => [], "models" => []} =
             RemoveOrganizationAIProvider.call(conn, %{"account_handle" => handle, "provider_id" => provider.id})[
               "structuredContent"
             ]
  end

  test "refuses members, scoped credentials without a user, other organizations' records and disabled organizations",
       %{admin: admin, organization: organization, account: account, handle: handle, provider: provider} do
    member = AccountsFixtures.user_fixture(preload: [:account])
    Accounts.add_user_to_organization(member, organization, role: :user)
    assert GetOrganizationAIConfiguration.call(user_conn(member), %{"account_handle" => handle})["isError"]

    agent = %Plug.Conn{
      assigns: %{current_subject: %AuthenticatedAccount{account: account, scopes: ["mcp"], all_projects: true}}
    }

    assert GetOrganizationAIConfiguration.call(agent, %{"account_handle" => handle})["isError"]

    other_admin = AccountsFixtures.user_fixture(preload: [:account])
    other = AccountsFixtures.organization_fixture(creator: other_admin, preload: [:account]).account
    stub(FeatureFlags, :organization_luft_enabled?, fn _ -> true end)

    foreign =
      SaveOrganizationAIModel.call(user_conn(other_admin), %{
        "account_handle" => other.name,
        "name" => "Foreign",
        "provider_id" => provider.id,
        "upstream_model_id" => "example"
      })

    assert %{"isError" => true, "content" => [%{"text" => text}]} = foreign
    assert text =~ "invalid"

    assert RemoveOrganizationAIProvider.call(user_conn(other_admin), %{
             "account_handle" => other.name,
             "provider_id" => provider.id
           })["isError"]

    stub(FeatureFlags, :organization_luft_enabled?, fn _ -> false end)

    assert %{"isError" => true, "content" => [%{"text" => text}]} =
             GetOrganizationAIConfiguration.call(user_conn(admin), %{"account_handle" => handle})

    assert text =~ "not available"
    stub(FeatureFlags, :organization_luft_enabled?, fn _ -> true end)
    assert {:ok, %{connections: [_]}} = OrganizationAI.settings(admin, account)
  end
end
