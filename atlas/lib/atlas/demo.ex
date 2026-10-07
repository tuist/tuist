defmodule Atlas.Demo do
  @moduledoc """
  Policy for the isolated public demo. New pages and events are denied until
  their page-load and interaction side effects have been reviewed.
  """

  alias Atlas.Users.User

  @views %{
    AtlasWeb.DemoLive => [],
    AtlasWeb.AccountsLive => ~w(search add_filter update_filter),
    AtlasWeb.AccountLive => [],
    AtlasWeb.TasksLive => ~w(search add_filter update_filter),
    AtlasWeb.FinanceLive =>
      ~w(search select_overview_widget runway_period_changed transactions_period_changed add_filter update_filter),
    AtlasWeb.FinanceVendorLive => ~w(search_expenses select_chart vendors_period_changed add_filter update_filter),
    AtlasWeb.NotesLive => ~w(search add_filter update_filter)
  }

  @paths [
    ~r{\A/(?:demo|tasks|commercial/sales/accounts|commercial/finance(?:/vendors)?|library/notes)\z},
    ~r"\A/(?:commercial/sales/accounts|library/notes)/[0-9a-f-]{36}\z"
  ]

  def enabled?, do: Application.get_env(:atlas, :demo_mode, false)

  def user do
    %User{id: "00000000-0000-4000-8000-000000000000", name: "Demo visitor", email: "visitor@example.invalid"}
  end

  def scopes, do: ~w(accounts:read finance:read notes:read)

  def allowed_view?(view), do: Map.has_key?(@views, view)

  def allowed_event?(view, event) do
    event == "search_palette_search" or event in Map.get(@views, view, [])
  end

  def dashboard_path?(path), do: Enum.any?(@paths, &Regex.match?(&1, path))

  def public_path?(path) do
    path in ["/", "/ready"] or dashboard_path?(path) or
      path in ["/docs", "/docs-markdown"] or
      String.starts_with?(path, "/docs/") or String.starts_with?(path, "/docs-markdown/")
  end

  # Migrations and seeding start the repository without starting Atlas.Application.
  # Only the serving process gets this extra database-level mutation barrier.
  def repo_options do
    [parameters: [default_transaction_read_only: "on"]]
  end
end
