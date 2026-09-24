defmodule TuistWeb.Components.OIDCScopeRules do
  @moduledoc """
  Lists write scopes with the OIDC scope rule configured for each, and edits
  them through a modal per scope.

  The hosting LiveView handles `save_oidc_rule`, `delete_oidc_rule`, and
  `close_oidc_rule_modal` through `handle_rule_event/4`.
  """
  use Phoenix.Component
  use Noora
  use Gettext, backend: TuistWeb.Gettext

  import Phoenix.LiveView, only: [push_event: 3, put_flash: 3]

  alias Phoenix.LiveView.JS
  alias Tuist.OIDC.ScopeRule

  attr(:id, :string, required: true)
  attr(:scopes, :list, required: true)
  attr(:rules, :map, required: true, doc: "Rules keyed by scope")
  attr(:errors, :map, default: %{}, doc: "Validation errors keyed by scope")

  def oidc_scope_rules(assigns) do
    assigns = assign(assigns, :row_key, fn scope -> "#{assigns.id}-#{slug(scope)}" end)

    ~H"""
    <.table id={@id} rows={@scopes} row_key={@row_key}>
      <:col :let={scope} label={dgettext("dashboard", "Permission")}>
        <.text_and_description_cell label={scope_label(scope)} description={scope} />
      </:col>
      <:col :let={scope} label={dgettext("dashboard", "Branches and tags")}>
        <.text_cell label={patterns_label(@rules, scope, :refs)} />
      </:col>
      <:col :let={scope} label={dgettext("dashboard", "Workflows")}>
        <.text_cell label={patterns_label(@rules, scope, :job_workflow_refs)} />
      </:col>
      <:col :let={scope} label={dgettext("dashboard", "Environments")}>
        <.text_cell label={patterns_label(@rules, scope, :environments)} />
      </:col>
      <:col :let={scope} label="">
        <.button_cell>
          <:button>
            <.form for={%{}} id={"#{@id}-#{slug(scope)}-form"} phx-submit="save_oidc_rule">
              <.modal
                id={"#{@id}-#{slug(scope)}-modal"}
                title={scope_label(scope)}
                header_size="large"
                on_dismiss={JS.push("close_oidc_rule_modal", value: %{scope: scope})}
              >
                <:trigger :let={attrs}>
                  <.button icon_only size="small" variant="secondary" {attrs}>
                    <.icon name="pencil" />
                  </.button>
                </:trigger>
                <.line_divider />
                <p data-part="alert-description">
                  {dgettext(
                    "dashboard",
                    "OIDC tokens from GitHub Actions can use %{scope} only when every field you fill in matches; other runs keep read access. Separate patterns with commas. * matches within a path segment and ** across segments.",
                    scope: scope
                  )}
                </p>
                <input type="hidden" name="scope" value={scope} />
                <div data-part="alert-form">
                  <div data-part="schedule-row">
                    <label data-part="schedule-label" for={"#{@id}-#{slug(scope)}-refs"}>
                      {dgettext("dashboard", "Branches and tags")}
                    </label>
                    <.text_input
                      id={"#{@id}-#{slug(scope)}-refs"}
                      type="basic"
                      name="refs"
                      value={patterns_value(@rules, scope, :refs)}
                      placeholder="refs/heads/main"
                      error={Map.get(@errors, scope)}
                    />
                  </div>
                  <div data-part="schedule-row">
                    <label data-part="schedule-label" for={"#{@id}-#{slug(scope)}-job-workflow-refs"}>
                      {dgettext("dashboard", "Workflows")}
                    </label>
                    <.text_input
                      id={"#{@id}-#{slug(scope)}-job-workflow-refs"}
                      type="basic"
                      name="job_workflow_refs"
                      value={patterns_value(@rules, scope, :job_workflow_refs)}
                      placeholder="org/repo/.github/workflows/release.yml@**"
                    />
                  </div>
                  <div data-part="schedule-row">
                    <label data-part="schedule-label" for={"#{@id}-#{slug(scope)}-environments"}>
                      {dgettext("dashboard", "Environments")}
                    </label>
                    <.text_input
                      id={"#{@id}-#{slug(scope)}-environments"}
                      type="basic"
                      name="environments"
                      value={patterns_value(@rules, scope, :environments)}
                      placeholder="release"
                    />
                  </div>
                </div>
                <.line_divider />
                <:footer>
                  <.modal_footer>
                    <:action :if={Map.has_key?(@rules, scope)}>
                      <.button
                        type="button"
                        label={dgettext("dashboard", "Remove rule")}
                        variant="destructive"
                        phx-click="delete_oidc_rule"
                        phx-value-scope={scope}
                      />
                    </:action>
                    <:action>
                      <.button
                        type="reset"
                        label={dgettext("dashboard", "Cancel")}
                        variant="secondary"
                        phx-click="close_oidc_rule_modal"
                        phx-value-scope={scope}
                      />
                    </:action>
                    <:action>
                      <.button type="submit" label={dgettext("dashboard", "Save")} variant="primary" />
                    </:action>
                  </.modal_footer>
                </:footer>
              </.modal>
            </.form>
          </:button>
        </.button_cell>
      </:col>
    </.table>
    """
  end

  attr(:providers, :list, required: true, doc: "Providers other than GitHub Actions seen recently")
  attr(:subject, :string, required: true, doc: "What the rules protect, e.g. \"project\"")
  attr(:rest, :global)

  def provider_notice(assigns) do
    ~H"""
    <.alert
      :if={@providers != []}
      status="warning"
      type="secondary"
      size="large"
      title={
        dgettext("dashboard", "%{providers} runs lose write access when a rule applies",
          providers: provider_names(@providers)
        )
      }
      description={
        dgettext(
          "dashboard",
          "This %{subject} received OIDC tokens from %{providers} in the last 30 days. Rules only match GitHub Actions tokens, so those runs lose write access for every permission that has a rule. Reads keep working.",
          subject: @subject,
          providers: provider_names(@providers)
        )
      }
      {@rest}
    />
    <.alert
      :if={@providers == []}
      status="information"
      type="secondary"
      size="large"
      title={dgettext("dashboard", "Rules only match GitHub Actions tokens")}
      description={
        dgettext(
          "dashboard",
          "OIDC tokens from CircleCI or Bitrise lose write access for every permission that has a rule. Reads keep working."
        )
      }
      {@rest}
    />
    """
  end

  defp provider_names(providers) do
    Enum.map_join(providers, dgettext("dashboard", " and "), fn
      :circleci -> "CircleCI"
      :bitrise -> "Bitrise"
      other -> to_string(other)
    end)
  end

  @doc """
  Handles the component's events for a LiveView. `put_rule` and `delete_rule`
  persist the change for the scope, and `list_rules` reloads the rules.
  """
  def handle_rule_event(event, params, socket, callbacks)

  def handle_rule_event("save_oidc_rule", %{"scope" => scope} = params, socket, callbacks) do
    attrs = %{
      refs: split_patterns(params["refs"]),
      job_workflow_refs: split_patterns(params["job_workflow_refs"]),
      environments: split_patterns(params["environments"])
    }

    case callbacks.put_rule.(scope, attrs) do
      {:ok, _rule} ->
        socket
        |> assign(:oidc_rules, rules_by_scope(callbacks.list_rules.()))
        |> assign(:oidc_rule_errors, %{})
        |> push_event("close-modal", %{id: "#{callbacks.id}-#{slug(scope)}-modal"})
        |> put_flash(:info, dgettext("dashboard", "OIDC rule saved."))

      {:error, %Ecto.Changeset{} = changeset} ->
        assign(
          socket,
          :oidc_rule_errors,
          Map.put(socket.assigns.oidc_rule_errors, scope, changeset_error(changeset))
        )
    end
  end

  def handle_rule_event("delete_oidc_rule", %{"scope" => scope}, socket, callbacks) do
    :ok = callbacks.delete_rule.(scope)

    socket
    |> assign(:oidc_rules, rules_by_scope(callbacks.list_rules.()))
    |> assign(:oidc_rule_errors, %{})
    |> push_event("close-modal", %{id: "#{callbacks.id}-#{slug(scope)}-modal"})
    |> put_flash(:info, dgettext("dashboard", "OIDC rule removed."))
  end

  def handle_rule_event("close_oidc_rule_modal", params, socket, callbacks) do
    socket = assign(socket, :oidc_rule_errors, %{})

    case params do
      %{"scope" => scope} -> push_event(socket, "close-modal", %{id: "#{callbacks.id}-#{slug(scope)}-modal"})
      _ -> socket
    end
  end

  def rules_by_scope(rules), do: Map.new(rules, &{&1.scope, &1})

  def project_scopes, do: ScopeRule.project_scopes()
  def account_scopes, do: ScopeRule.account_scopes()

  defp split_patterns(nil), do: []

  defp split_patterns(value) do
    value
    |> String.split([",", "\n"])
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp changeset_error(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc -> String.replace(acc, "%{#{key}}", to_string(value)) end)
    end)
    |> Enum.flat_map(fn {_field, messages} -> messages end)
    |> Enum.join(". ")
  end

  defp patterns_label(rules, scope, field) do
    case patterns_value(rules, scope, field) do
      "" -> dgettext("dashboard", "Any")
      value -> value
    end
  end

  defp patterns_value(rules, scope, field) do
    case Map.get(rules, scope) do
      nil -> ""
      rule -> Enum.join(Map.fetch!(rule, field), ", ")
    end
  end

  defp slug(scope), do: String.replace(scope, ":", "-")

  defp scope_label("project:cache:write"), do: dgettext("dashboard", "Cache uploads")
  defp scope_label("project:previews:write"), do: dgettext("dashboard", "Preview uploads")
  defp scope_label("project:bundles:write"), do: dgettext("dashboard", "Bundle uploads")
  defp scope_label("project:tests:write"), do: dgettext("dashboard", "Test results")
  defp scope_label("project:builds:write"), do: dgettext("dashboard", "Build insights")
  defp scope_label("project:runs:write"), do: dgettext("dashboard", "Command runs")
  defp scope_label("account:cache:write"), do: dgettext("dashboard", "Account-wide cache uploads")
  defp scope_label(scope), do: scope
end
