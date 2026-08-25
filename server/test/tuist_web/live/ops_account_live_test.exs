defmodule TuistWeb.OpsAccountLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Accounts
  alias Tuist.Billing
  alias Tuist.Kura
  alias Tuist.Kura.AccountPolicies
  alias Tuist.Kura.Server
  alias Tuist.Repo
  alias Tuist.Runners.Concurrency
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  setup :verify_on_exit!

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    conn = log_in_user(conn, user)

    stub(Accounts, :tuist_operator?, fn _ -> true end)

    %{conn: conn, user: user}
  end

  test "renders account billing controls", %{conn: conn, user: user} do
    {:ok, _lv, html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

    assert html =~ user.account.name
    assert html =~ "Plan &amp; billing"
    assert html =~ "Kura"
    assert html =~ "Runner concurrency"
    assert html =~ "value=\"12\""
  end

  test "toggles the account's dashboard visibility", %{conn: conn, user: user} do
    {:ok, lv, html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

    assert html =~ "Make public"

    html = lv |> element("button", "Make public") |> render_click()

    assert html =~ "Make private"
    assert {:ok, %{visibility: :public}} = Accounts.get_account_by_id(user.account.id)

    lv |> element("button", "Make private") |> render_click()

    assert {:ok, %{visibility: :private}} = Accounts.get_account_by_id(user.account.id)
  end

  test "updates platform-specific runner concurrency limits", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

    lv
    |> form("#runner-concurrency-form", %{
      "account" => %{
        "runner_linux_vcpus_limit" => "48",
        "runner_linux_memory_gb_limit" => "96",
        "runner_macos_vcpus_limit" => "18",
        "runner_macos_memory_gb_limit" => "42"
      }
    })
    |> render_submit()

    assert Concurrency.limits_for(user.account, :linux) == %{vcpus: 48, memory_gb: 96}
    assert Concurrency.limits_for(user.account, :macos) == %{vcpus: 18, memory_gb: 42}
  end

  test "links Kura servers to their latest deployment", %{conn: conn, user: user} do
    {:ok, server} =
      Kura.create_server(%{
        account_id: user.account.id,
        region: "local-controller",
        image_tag: "0.5.2"
      })

    deployment = List.first(server.deployments)

    {:ok, _lv, html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

    assert html =~ "0.5.2"
    refute html =~ "kura@0.5.2"
    assert html =~ ~p"/ops/accounts/#{user.account.id}/kura/deployments/#{deployment.id}"
  end

  test "shows the claim each instance actually holds", %{conn: conn, user: user} do
    stub(Tuist.Environment, :tuist_hosted?, fn -> true end)

    # Pinned: what this instance's volumes were created at, which diverges from
    # what its account would be sized at today for as long as it holds them, and
    # nothing converges the two on its own.
    Repo.insert!(%Server{
      account_id: user.account.id,
      region: "us-east",
      status: :active,
      url: "https://acme-us-east-1.kura.tuist.dev",
      current_image_tag: "0.5.2",
      provisioner_node_ref: "kura-#{user.account.id}-us-east",
      storage_claim_size: "50Gi"
    })

    # Pins nothing, and its region sizes every instance alike rather than per
    # account, so it holds the region's own claim. Reading the pinned column
    # alone reported "None" here while the instance was reserving 10Gi.
    Repo.insert!(%Server{
      account_id: user.account.id,
      region: "local-controller",
      status: :active,
      url: "http://localhost:4100",
      current_image_tag: "0.5.2",
      provisioner_node_ref: "kura-#{user.account.id}-local-controller"
    })

    {:ok, _lv, html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

    assert html =~ "50Gi"
    assert html =~ "10Gi"
  end

  test "resolves an unpinned instance in a per-account region against the override", %{conn: conn, user: user} do
    stub(Tuist.Environment, :tuist_hosted?, fn -> true end)

    # A governed region pins at creation, so this row is the state the resolution
    # exists to cover rather than one the product creates. It holds whatever the
    # account resolves to, which is the override once there is one.
    Repo.insert!(%Server{
      account_id: user.account.id,
      region: "us-east",
      status: :active,
      url: "https://acme-us-east-1.kura.tuist.dev",
      current_image_tag: "0.5.2",
      provisioner_node_ref: "kura-#{user.account.id}-us-east"
    })

    {:ok, _lv, html} = live(conn, ~p"/ops/accounts/#{user.account.id}")
    assert html =~ "8Gi"

    {:ok, _} = Kura.update_storage_claim_override(user.account, %{"kura_storage_claim_size" => "24Gi"})

    {:ok, _lv, html} = live(conn, ~p"/ops/accounts/#{user.account.id}")
    assert html =~ "24Gi"
  end

  test "sets a claim override and re-pins the instance it rebuilds", %{conn: conn, user: user} do
    stub(Tuist.Environment, :tuist_hosted?, fn -> true end)

    server =
      Repo.insert!(%Server{
        account_id: user.account.id,
        region: "us-east",
        status: :active,
        url: "https://acme-us-east-1.kura.tuist.dev",
        current_image_tag: "0.5.2",
        provisioner_node_ref: "kura-#{user.account.id}-us-east",
        storage_claim_size: "8Gi"
      })

    {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

    html =
      lv
      |> form("#kura-storage-claim-form", account: %{kura_storage_claim_size: "40Gi"})
      |> render_submit()

    assert Kura.storage_claim_override(user.account) == "40Gi"

    # Re-pinned, which is what carries the new claim into the manifest and has
    # the controller rebuild the volumes that no longer match it.
    assert Repo.get!(Server, server.id).storage_claim_size == "40Gi"

    # And the table the operator is looking at reflects it without a reload.
    assert html =~ "40Gi"
  end

  test "clears the override from the form and returns the account to its plan", %{conn: conn, user: user} do
    stub(Tuist.Environment, :tuist_hosted?, fn -> true end)

    {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

    lv
    |> form("#kura-storage-claim-form", account: %{kura_storage_claim_size: "40Gi"})
    |> render_submit()

    lv
    |> form("#kura-storage-claim-form", account: %{kura_storage_claim_size: ""})
    |> render_submit()

    assert Kura.storage_claim_override(user.account) == nil
  end

  test "refuses a claim below the floor a ring can be derived from", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

    html =
      lv
      |> form("#kura-storage-claim-form", account: %{kura_storage_claim_size: "4Gi"})
      |> render_submit()

    assert html =~ "must be at least 8Gi"
    assert Kura.storage_claim_override(user.account) == nil
  end

  test "one-click upgrade when the Stripe customer already has billing details", %{conn: conn, user: user} do
    stub(Stripe.Customer, :retrieve, fn _customer_id ->
      {:ok,
       %Stripe.Customer{
         name: "Acme",
         email: "billing@acme.test",
         address: %{
           line1: "1 Market St",
           city: "SF",
           postal_code: "94103",
           country: "US"
         }
       }}
    end)

    expect(Billing, :upgrade_to_enterprise, fn account, params ->
      assert account.id == user.account.id
      assert params == %{cadence: "monthly"}
      {:ok, %{id: "sub_fake"}}
    end)

    {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

    render_hook(lv, "initiate_enterprise_upgrade", %{})
  end

  test "opens the enterprise form when the Stripe customer has no address", %{conn: conn, user: user} do
    stub(Stripe.Customer, :retrieve, fn _customer_id ->
      {:ok, %Stripe.Customer{name: "Acme", email: "acme@test", address: nil}}
    end)

    {:ok, lv, initial_html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

    refute initial_html =~ "Upgrade #{user.account.name} to Enterprise"

    html = render_hook(lv, "initiate_enterprise_upgrade", %{})

    assert html =~ "Upgrade #{user.account.name} to Enterprise"
  end

  test "submits the enterprise form with the collected billing details", %{conn: conn, user: user} do
    expect(Billing, :upgrade_to_enterprise, fn account, params ->
      assert account.id == user.account.id
      assert params.name == "Acme Corp"
      assert params.billing_email == "billing@acme.test"
      assert params.cadence == "yearly"
      assert params.address.line1 == "1 Market St"
      assert params.address.city == "San Francisco"
      assert params.address.postal_code == "94103"
      assert params.address.country == "US"
      {:ok, %{id: "sub_fake"}}
    end)

    {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

    render_hook(lv, "submit_enterprise_upgrade", %{
      "name" => "Acme Corp",
      "billing_email" => "billing@acme.test",
      "address_line1" => "1 Market St",
      "address_line2" => "",
      "address_city" => "San Francisco",
      "address_state" => "CA",
      "address_postal_code" => "94103",
      "address_country" => "us",
      "cadence" => "yearly"
    })
  end

  test "Cancel plan cancels the active subscription at period end", %{conn: conn, user: user} do
    subscription = BillingFixtures.subscription_fixture(account_id: user.account.id, plan: :pro)

    expect(Billing, :cancel_subscription_at_period_end, fn sub ->
      assert sub.id == subscription.id
      {:ok, %{id: subscription.subscription_id, cancel_at_period_end: true}}
    end)

    {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

    render_hook(lv, "cancel_plan", %{})
  end

  describe "Kura placement" do
    test "shows the resolved region and offers every assignable one", %{conn: conn, user: user} do
      BillingFixtures.subscription_fixture(account_id: user.account.id, plan: :pro)

      {:ok, _lv, html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

      assert html =~ "Kura placement"
      # A paid account allowing every storage region and holding no instance
      # falls through to the deterministic default, which is the state the
      # assignment exists to correct.
      assert html =~ "US East (us-east)"
      assert html =~ "kura-assignment-form"

      # The picker is driven by `AccountRegionPolicy.service_regions/0`, which
      # is the only route to a region no storage preference derives to.
      assert html =~ "US West (us-west)"
      assert html =~ "EU Central (eu-central)"
    end

    test "assigns a service region with the operator's own reason", %{conn: conn, user: user} do
      BillingFixtures.subscription_fixture(account_id: user.account.id, plan: :pro)

      {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

      html =
        lv
        |> form("#kura-assignment-form", %{
          "assignment" => %{
            "service_region" => "eu-central",
            "reason" => "99.8 percent of cache endpoint picks are eu-central over 90 days"
          }
        })
        |> render_submit()

      assignment = AccountPolicies.current_service_region_assignment(user.account)
      assert assignment.service_region == "eu-central"
      assert assignment.version == 1
      assert assignment.assigned_by_user_id == user.id
      assert assignment.reason == "99.8 percent of cache endpoint picks are eu-central over 90 days"

      # The card the operator is looking at moves with the write: the account
      # now resolves to the assigned region, and the reason and actor land in
      # the audit trail below it.
      assert html =~ "EU Central (eu-central)"
      assert html =~ "99.8 percent of cache endpoint picks are eu-central over 90 days"
      assert html =~ user.email

      # And the write says what it deliberately did not do, since a destroy
      # that lands before the redirected demand is undone by that demand.
      assert html =~ "destroy the one in the old region only once that has happened"
    end

    test "clears the reason once an assignment lands and keeps it when one is refused", %{conn: conn, user: user} do
      BillingFixtures.subscription_fixture(account_id: user.account.id, plan: :pro)

      {:ok, lv, html} = live(conn, ~p"/ops/accounts/#{user.account.id}")
      assert html =~ ~s(id="kura-assignment-reason-0")

      # A refused write leaves the operator's reason where it is: nothing landed,
      # so there is nothing to retype.
      html =
        lv
        |> form("#kura-assignment-form", %{
          "assignment" => %{"service_region" => "eu-central", "reason" => ""}
        })
        |> render_submit()

      assert html =~ "Could not assign a service region"
      assert html =~ ~s(id="kura-assignment-reason-0")

      html =
        lv
        |> form("#kura-assignment-form", %{
          "assignment" => %{"service_region" => "eu-central", "reason" => "Measured demand is European"}
        })
        |> render_submit()

      # The input is browser-owned state, so re-rendering it with the same empty
      # value produces no diff and the browser keeps whatever was typed — the
      # next assignment would silently inherit the last one's reason. Keying the
      # id on the number of assignments replaces the node exactly when one lands.
      assert html =~ ~s(id="kura-assignment-reason-1")
      refute html =~ ~s(id="kura-assignment-reason-0")
    end

    test "explains that an Air account can never be assigned instead of offering a form", %{conn: conn, user: user} do
      {:ok, _lv, html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

      assert html =~ "Only Pro and Enterprise accounts can be assigned a service region"
      refute html =~ "kura-assignment-form"
    end

    test "explains that an account whose storage region decides placement cannot be overridden", %{
      conn: conn,
      user: user
    } do
      BillingFixtures.subscription_fixture(account_id: user.account.id, plan: :enterprise)
      {:ok, _account} = Accounts.update_account(user.account, %{region: :usa})

      {:ok, _lv, html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

      assert html =~ "service region is derived from that and must not be overridden here"
      refute html =~ "kura-assignment-form"
    end

    test "distinguishes a plan with no Kura pool from a plan that cannot be assigned", %{conn: conn, user: user} do
      BillingFixtures.subscription_fixture(account_id: user.account.id, plan: :open_source)

      {:ok, _lv, html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

      # `:plan_not_supported` comes back from both `resolve/1` and the
      # assignment check and means something different in each: Open Source has
      # no pool at all, where Air merely cannot be pinned.
      assert html =~ "Unresolved"
      assert html =~ "this account is on a plan no Kura pool serves"
      assert html =~ "and this one is on Open Source"
      refute html =~ "kura-assignment-form"
    end

    test "restores a superseded assignment as a new version with a fresh reason", %{conn: conn, user: user} do
      BillingFixtures.subscription_fixture(account_id: user.account.id, plan: :pro)

      {:ok, first} =
        AccountPolicies.assign_service_region(user.account, "us-east", user, "Initial placement")

      {:ok, _second} =
        AccountPolicies.assign_service_region(user.account, "eu-central", user, "Regional move")

      {:ok, lv, html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

      # Only the superseded row can be restored; re-applying the current one
      # would append a version that changes nothing.
      assert html =~ "Restore"

      html = render_click(lv, "open_restore_kura_assignment", %{"version" => to_string(first.version)})
      assert html =~ "Restore version 1"

      # The form itself lives in the modal's portal, which LiveViewTest does not
      # select through, so the submit is driven by its event the way the other
      # modal-backed pages drive theirs.
      render_submit(lv, "restore_kura_assignment", %{
        "assignment" => %{
          "version" => to_string(first.version),
          "reason" => "Rolling back the regional move"
        }
      })

      restored = AccountPolicies.current_service_region_assignment(user.account)
      assert restored.version == 3
      assert restored.service_region == "us-east"
      assert restored.reason == "Rolling back the regional move"

      # Nothing is rewritten: every earlier version is still in the trail.
      assert length(AccountPolicies.list_service_region_history(user.account)) == 3
    end

    test "reports a refused restore rather than failing silently", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

      html = render_click(lv, "open_restore_kura_assignment", %{"version" => "42"})

      assert html =~ "That assignment no longer exists."
    end
  end

  describe "Kura instances" do
    setup do
      stub(Tuist.Environment, :kura_runtime_image_tag, fn -> "0.5.2" end)
      :ok
    end

    test "provisions an instance in a region the account does not already hold", %{conn: conn, user: user} do
      {:ok, lv, html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

      assert html =~ "No Kura instances"

      html =
        lv
        |> form("#kura-provision-form", %{"instance" => %{"region" => "local-controller"}})
        |> render_submit()

      assert [%Server{region: "local-controller", status: :provisioning}] =
               Kura.list_servers_for_account(user.account.id)

      assert html =~ "Provisioning a Kura instance in local-controller."

      # A region the account now holds is off the picker: the partial
      # uniqueness index counts the row as owning it, so a second instance
      # there would only fail to insert.
      refute html =~ "kura-provision-form"
      assert html =~ "already holds an instance in every region it can be provisioned in"
    end

    test "refuses a region that is not on the picker", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

      # `Kura.create_server/1` accepts every region in `Regions.available/0`,
      # which is wider than what this card offers, and the params are
      # client-controlled.
      html = render_submit(lv, "provision_kura_instance", %{"instance" => %{"region" => "scw-fr-par-runners"}})

      assert html =~ "Pick a region this account can be provisioned in."
      assert Kura.list_servers_for_account(user.account.id) == []
    end

    test "destroys an instance and says what the destroy did", %{conn: conn, user: user} do
      {:ok, server} =
        Kura.create_server(%{
          account_id: user.account.id,
          region: "local-controller",
          image_tag: "0.5.2"
        })

      {:ok, lv, html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

      # The confirmation names both the region and the status the operator is
      # about to tear down, and the ordering the lifecycle imposes.
      assert html =~ "Destroy the provisioning Kura instance in local-controller?"
      assert html =~ "cache demand recorded after this destroy re-provisions the instance right here"

      html = render_click(lv, "destroy_kura_instance", %{"id" => server.id})

      assert Repo.get!(Server, server.id).status == :destroying
      assert html =~ "Destroying the Kura instance in local-controller."
    end

    test "reports a destroy of an instance that is already gone", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

      html = render_click(lv, "destroy_kura_instance", %{"id" => Ecto.UUID.generate()})

      assert html =~ "That Kura instance no longer exists."
    end

    test "refuses to provision while no runtime image is configured", %{conn: conn, user: user} do
      stub(Tuist.Environment, :kura_runtime_image_tag, fn -> nil end)

      {:ok, lv, html} = live(conn, ~p"/ops/accounts/#{user.account.id}")

      assert html =~ "No Kura runtime image is configured right now"

      html = render_submit(lv, "provision_kura_instance", %{"instance" => %{"region" => "local-controller"}})

      assert html =~ "No Kura runtime image is configured right now"
      assert Kura.list_servers_for_account(user.account.id) == []
    end
  end
end
