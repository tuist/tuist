defmodule TuistWeb.RunnerProfilesLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Repo
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.Profile
  alias Tuist.Runners.Profiles
  alias TuistTestSupport.Fixtures.AccountsFixtures

  @catalog [
    %{vcpus: 1, memory_gb: 2, key: "1vcpu-2gb", default?: false, pool_dispatch_label: ""},
    %{vcpus: 4, memory_gb: 16, key: "4vcpu-16gb", default?: true, pool_dispatch_label: ""},
    %{vcpus: 8, memory_gb: 32, key: "8vcpu-32gb", default?: false, pool_dispatch_label: ""}
  ]

  setup %{conn: conn} do
    stub(Catalog, :shapes, fn
      :linux -> @catalog
      :macos -> []
    end)

    stub(Catalog, :default_shape, fn
      :linux -> Enum.find(@catalog, & &1.default?)
      :macos -> nil
    end)

    stub(Catalog, :xcode_versions, fn -> [] end)
    stub(Catalog, :default_xcode_version, fn -> nil end)

    user = AccountsFixtures.user_fixture()

    %{account: account} =
      AccountsFixtures.organization_fixture(
        name: "profiles-ui-#{System.unique_integer([:positive])}",
        creator: user,
        preload: [:account]
      )

    conn =
      conn
      |> assign(:selected_account, account)
      |> log_in_user(user)

    %{conn: conn, user: user, account: account}
  end

  describe "list page" do
    test "renders the protected linux default that ships with every account",
         %{conn: conn, account: account} do
      # Every account is auto-bootstrapped with the protected `linux`
      # profile (see `Accounts.create_user`/`create_organization`), so
      # the page always shows at least one row — the empty state is
      # only reachable from a manually-broken DB state.
      {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners/profiles")

      assert html =~ "tuist-linux"
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

    test "request + confirm deletes the profile", %{conn: conn, account: account} do
      {:ok, profile} = Profiles.create(account, %{"name" => "default", "vcpus" => 4, "memory_gb" => 16})
      {:ok, _} = Profiles.create(account, %{"name" => "large", "vcpus" => 8, "memory_gb" => 32})

      {:ok, lv, _} = live(conn, ~p"/#{account.name}/runners/profiles")

      # Row action opens the confirm modal; only the confirm commits.
      render_hook(lv, "request_delete_profile", %{"id" => to_string(profile.id)})
      assert Profiles.get_by_name(account, "default")

      render_hook(lv, "confirm_delete_profile", %{})
      refute Profiles.get_by_name(account, "default")
      assert Profiles.get_by_name(account, "large")
    end

    test "cancel keeps the profile", %{conn: conn, account: account} do
      {:ok, profile} = Profiles.create(account, %{"name" => "default", "vcpus" => 4, "memory_gb" => 16})
      {:ok, _} = Profiles.create(account, %{"name" => "large", "vcpus" => 8, "memory_gb" => 32})

      {:ok, lv, _} = live(conn, ~p"/#{account.name}/runners/profiles")

      render_hook(lv, "request_delete_profile", %{"id" => to_string(profile.id)})
      render_hook(lv, "cancel_delete_profile", %{})
      assert Profiles.get_by_name(account, "default")
    end

    test "refuses to delete a protected profile", %{conn: conn, account: account} do
      # `:account` is already auto-bootstrapped with the protected `linux`
      # profile by `Accounts.create_user`. Add a user-created sibling so
      # the "only remaining" count-based guard doesn't mask the protected
      # guard — the row count is fine, the protection itself is what
      # should reject the delete.
      default = Profiles.get_by_name(account, "linux")
      assert default.protected
      {:ok, _other} = Profiles.create(account, %{"name" => "other", "vcpus" => 4, "memory_gb" => 16})

      {:ok, lv, html} = live(conn, ~p"/#{account.name}/runners/profiles")
      # Row action is hidden for protected rows.
      refute html =~ ~s(phx-value-id="#{default.id}" phx-click="request_delete_profile")

      # Crafted request still bounces off the server-side guard with
      # the flash, and the row survives.
      render_hook(lv, "request_delete_profile", %{"id" => to_string(default.id)})
      render_hook(lv, "confirm_delete_profile", %{})
      assert Profiles.get_by_name(account, "linux")
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

  describe "profiles on an Xcode version the catalog doesn't list" do
    setup %{account: account} do
      macos_shape = %{vcpus: 6, memory_gb: 14, key: "6vcpu-14gb", default?: true}

      stub(Catalog, :shapes, fn
        :linux -> @catalog
        :macos -> [macos_shape]
      end)

      stub(Catalog, :xcode_versions, fn -> [%{xcode_version: "26.6", tag: "26-6", default?: true}] end)

      hidden =
        Repo.insert!(%Profile{
          account_id: account.id,
          name: "hidden-xcode",
          platform: :macos,
          vcpus: 6,
          memory_gb: 14,
          xcode_version: "26.1.1"
        })

      available =
        Repo.insert!(%Profile{
          account_id: account.id,
          name: "available-xcode",
          platform: :macos,
          vcpus: 6,
          memory_gb: 14,
          xcode_version: "26.6"
        })

      %{hidden: hidden, available: available}
    end

    test "warns about the profiles whose jobs won't start",
         %{conn: conn, account: account, hidden: hidden, available: available} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/runners/profiles")

      assert has_element?(lv, "#runner-profile-unavailable-xcode-#{hidden.id}", "tuist-hidden-xcode")
      refute has_element?(lv, "#runner-profile-unavailable-xcode-#{available.id}")
    end

    test "editing requires choosing an available Xcode version", %{conn: conn, account: account, hidden: hidden} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/runners/profiles")

      # The modal body renders through a portal, which `has_element?/2` doesn't search.
      assert render_hook(lv, "open_edit_modal", %{"id" => to_string(hidden.id)}) =~
               ~s(id="runner-profile-xcode-version-unavailable")

      render_hook(lv, "save_profile", %{})
      assert %{xcode_version: "26.1.1"} = Profiles.get_by_name(account, "hidden-xcode")

      refute render_hook(lv, "select_xcode_version", %{"data" => "26.6"}) =~
               ~s(id="runner-profile-xcode-version-unavailable")

      render_hook(lv, "save_profile", %{})
      assert %{xcode_version: "26.6"} = Profiles.get_by_name(account, "hidden-xcode")
      refute has_element?(lv, "#runner-profile-unavailable-xcode-#{hidden.id}")
    end
  end
end
