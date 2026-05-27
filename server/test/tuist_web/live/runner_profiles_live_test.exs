defmodule TuistWeb.RunnerProfilesLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Runners.Catalog
  alias Tuist.Runners.Profiles
  alias TuistTestSupport.Fixtures.AccountsFixtures

  @catalog [
    %{vcpus: 1, memory_gb: 2, key: "1vcpu-2gb", default?: false, pool_dispatch_label: ""},
    %{vcpus: 4, memory_gb: 16, key: "4vcpu-16gb", default?: true, pool_dispatch_label: ""},
    %{vcpus: 8, memory_gb: 32, key: "8vcpu-32gb", default?: false, pool_dispatch_label: ""}
  ]

  setup %{conn: conn} do
    stub(Catalog, :list, fn -> @catalog end)
    stub(Catalog, :default, fn -> Enum.find(@catalog, & &1.default?) end)

    user = AccountsFixtures.user_fixture()

    %{account: account} =
      AccountsFixtures.organization_fixture(
        name: "profiles-ui-#{System.unique_integer([:positive])}",
        creator: user,
        preload: [:account]
      )

    account
    |> Ecto.Changeset.change(runner_max_concurrent: 5)
    |> Tuist.Repo.update!()

    conn =
      conn
      |> assign(:selected_account, account)
      |> log_in_user(user)

    %{conn: conn, user: user, account: account}
  end

  describe "list page" do
    test "renders the empty state when no profiles exist", %{conn: conn, account: account} do
      {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners/profiles")

      assert html =~ "No profiles yet"
    end

    test "lists existing profiles with their runs-on snippet", %{conn: conn, account: account} do
      {:ok, _} = Profiles.create(account, %{"name" => "default", "vcpus" => 4, "memory_gb" => 16})
      {:ok, _} = Profiles.create(account, %{"name" => "large", "vcpus" => 8, "memory_gb" => 32})

      {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners/profiles")

      assert html =~ "default"
      assert html =~ "tuist-default"
      assert html =~ "large"
      assert html =~ "tuist-large"
    end

    test "delete-profile removes the row", %{conn: conn, account: account} do
      {:ok, profile} = Profiles.create(account, %{"name" => "default", "vcpus" => 4, "memory_gb" => 16})
      {:ok, _} = Profiles.create(account, %{"name" => "large", "vcpus" => 8, "memory_gb" => 32})

      {:ok, lv, _} = live(conn, ~p"/#{account.name}/runners/profiles")

      assert lv
             |> element("button[phx-value-id='#{profile.id}']")
             |> render_click() =~ "large"

      refute Profiles.get_by_name(account, "default")
    end
  end

  describe "form page" do
    test "creating a valid profile redirects to the list", %{conn: conn, account: account} do
      {:ok, lv, _} = live(conn, ~p"/#{account.name}/runners/profiles/new")

      assert {:error, {:live_redirect, %{to: path}}} =
               lv
               |> form("#runner-profile-form",
                 profile: %{"name" => "default", "shape" => "4vcpu-16gb"}
               )
               |> render_submit()

      assert path == "/#{account.name}/runners/profiles"
      assert %{name: "default", vcpus: 4, memory_gb: 16} = Profiles.get_by_name(account, "default")
    end

    test "rejects an empty name on submit", %{conn: conn, account: account} do
      {:ok, lv, _} = live(conn, ~p"/#{account.name}/runners/profiles/new")

      html =
        lv
        |> form("#runner-profile-form",
          profile: %{"name" => "", "shape" => "4vcpu-16gb"}
        )
        |> render_submit()

      assert html =~ "can&#39;t be blank" or html =~ "must start with a letter"
    end

    test "editing an existing profile updates resources, name is immutable", %{conn: conn, account: account} do
      {:ok, _} = Profiles.create(account, %{"name" => "default", "vcpus" => 4, "memory_gb" => 16})

      {:ok, lv, _} = live(conn, ~p"/#{account.name}/runners/profiles/default")

      assert {:error, {:live_redirect, _}} =
               lv
               |> form("#runner-profile-form",
                 profile: %{"shape" => "8vcpu-32gb"}
               )
               |> render_submit()

      assert %{name: "default", vcpus: 8, memory_gb: 32} = Profiles.get_by_name(account, "default")
    end
  end
end
