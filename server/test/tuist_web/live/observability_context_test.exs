defmodule TuistWeb.ObservabilityContextTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Phoenix.LiveView.Lifecycle
  alias Phoenix.LiveView.Socket
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.User
  alias Tuist.Environment
  alias Tuist.Observability
  alias Tuist.Projects.Project
  alias TuistWeb.LayoutLive

  setup :set_mimic_from_context

  setup do
    stub(Environment, :error_tracking_enabled?, fn -> true end)
    :ok
  end

  test "mount registers hooks and callback spans receive current selected IDs and effective cohorts" do
    parent = self()
    stub(OpenTelemetry.Tracer, :set_attribute, fn key, value -> send(parent, {:attribute, key, value}) end)
    account = %Account{id: 42, name: "organization"}
    project = %Project{id: 99, account_id: account.id, account: account, name: "app"}

    socket = %Socket{
      router: TuistWeb.Router,
      assigns: %{
        __changed__: %{},
        current_user: %User{id: 7, account: %Account{id: 1, name: "personal"}},
        selected_project: project
      },
      private: %{lifecycle: %Lifecycle{}}
    }

    assert {:cont, mounted} = LayoutLive.on_mount(:observability, %{}, %{}, socket)
    assert_receive {:attribute, "selected_project_id", 99}
    assert Sentry.Context.get_all().tags.auth_account_id == 1
    assert Sentry.Context.get_all().tags.selected_account_id == 42

    for stage <- [:handle_params, :handle_event, :handle_info, :handle_async] do
      assert [%{id: :observability}] = Map.fetch!(mounted.private.lifecycle, stage)
    end

    Observability.feature_flag_evaluated(:runners, account, true)
    assert_receive {:attribute, "feature_flag.runners", "true"}

    assert {:cont, ^mounted} = LayoutLive.observability_callback("click", %{}, mounted)
    assert_receive {:attribute, "feature_flag.runners", "true"}

    switched = %{mounted | assigns: %{__changed__: %{}, selected_account: %Account{id: 43, name: "other"}}}
    assert {:cont, ^switched} = LayoutLive.observability_callback(:message, switched)
    assert Sentry.Context.get_all().tags.selected_account_id == 43
    refute Map.has_key?(Sentry.Context.get_all().tags, "feature_flag.runners")
    refute Map.has_key?(Sentry.Context.get_all().tags, :selected_project_id)
    refute Map.has_key?(Sentry.Context.get_all().tags, :auth_user_id)
  end

  test "embedded LiveViews do not attach a router-only handle_params hook" do
    socket = %Socket{private: %{lifecycle: %Lifecycle{}}}
    assert {:cont, mounted} = LayoutLive.on_mount(:observability, %{}, %{}, socket)
    assert mounted.private.lifecycle.handle_params == []
    assert [%{id: :observability}] = mounted.private.lifecycle.handle_event
  end
end
