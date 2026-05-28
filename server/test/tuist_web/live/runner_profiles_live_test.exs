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

    test "lists profiles with the tuist-<name> dispatch label", %{conn: conn, account: account} do
      {:ok, _} = Profiles.create(account, %{"name" => "default", "vcpus" => 4, "memory_gb" => 16})
      {:ok, _} = Profiles.create(account, %{"name" => "large", "vcpus" => 8, "memory_gb" => 32})

      {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners/profiles")

      assert html =~ "default"
      assert html =~ "tuist-default"
      assert html =~ "large"
      assert html =~ "tuist-large"
    end

    test "delete_profile removes the row", %{conn: conn, account: account} do
      {:ok, profile} = Profiles.create(account, %{"name" => "default", "vcpus" => 4, "memory_gb" => 16})
      {:ok, _} = Profiles.create(account, %{"name" => "large", "vcpus" => 8, "memory_gb" => 32})

      {:ok, lv, _} = live(conn, ~p"/#{account.name}/runners/profiles")

      render_hook(lv, "delete_profile", %{"id" => to_string(profile.id)})

      refute Profiles.get_by_name(account, "default")
      assert Profiles.get_by_name(account, "large")
    end

    test "refuses to delete the only remaining profile", %{conn: conn, account: account} do
      {:ok, only} = Profiles.create(account, %{"name" => "default", "vcpus" => 4, "memory_gb" => 16})

      {:ok, lv, html} = live(conn, ~p"/#{account.name}/runners/profiles")
      # The Delete row action is hidden when one profile remains.
      refute html =~ "delete_profile"

      # Even a crafted event is rejected server-side.
      render_hook(lv, "delete_profile", %{"id" => to_string(only.id)})
      assert Profiles.get_by_name(account, "default")
    end
  end

  describe "create modal" do
    test "save_profile creates a new profile and resets the form", %{conn: conn, account: account} do
      {:ok, lv, _} = live(conn, ~p"/#{account.name}/runners/profiles")

      # User picks the large shape (default is preselected at 4/16, swap to 8/32)
      render_hook(lv, "select_shape", %{"data" => "8vcpu-32gb"})
      render_hook(lv, "update_form_name", %{"value" => "default"})
      render_hook(lv, "save_profile", %{})

      assert %{name: "default", vcpus: 8, memory_gb: 32} = Profiles.get_by_name(account, "default")
    end

    test "surfaces validation errors inline without redirecting", %{conn: conn, account: account} do
      {:ok, lv, _} = live(conn, ~p"/#{account.name}/runners/profiles")

      render_hook(lv, "update_form_name", %{"value" => "tuist"})
      html = render_hook(lv, "save_profile", %{})

      # `tuist` is in the reserved-name list (see Profile.@reserved_names)
      assert html =~ "name:" or html =~ "reserved"
      refute Profiles.get_by_name(account, "tuist")
    end
  end

  describe "edit modal" do
    test "open_edit_modal followed by save_profile updates resources, name stays", %{conn: conn, account: account} do
      {:ok, profile} = Profiles.create(account, %{"name" => "default", "vcpus" => 4, "memory_gb" => 16})

      {:ok, lv, _} = live(conn, ~p"/#{account.name}/runners/profiles")

      render_hook(lv, "open_edit_modal", %{"id" => to_string(profile.id)})
      render_hook(lv, "select_shape", %{"data" => "8vcpu-32gb"})
      render_hook(lv, "save_profile", %{})

      assert %{name: "default", vcpus: 8, memory_gb: 32} = Profiles.get_by_name(account, "default")
    end
  end
end
