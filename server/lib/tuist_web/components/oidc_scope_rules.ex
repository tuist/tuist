defmodule TuistWeb.Components.OIDCScopeRules do
  @moduledoc """
  Lists write scopes with the OIDC scope rule configured for each, and edits
  them through a modal per scope.

  The hosting LiveView handles `save_oidc_rule`, `delete_oidc_rule`, and
  `close_oidc_rule_modal` through `handle_rule_event/3`.
  """
  use Phoenix.Component
  use Noora
  use Gettext, backend: TuistWeb.Gettext

  import Phoenix.LiveView, only: [push_event: 3, put_flash: 3]

  alias Tuist.OIDC.ScopeRule

  attr(:id, :string, required: true)
  attr(:scopes, :list, required: true)
  attr(:rules, :map, required: true, doc: "Rules keyed by scope")
  attr(:errors, :map, default: %{}, doc: "Validation errors keyed by scope")

  def oidc_scope_rules(assigns) do
    ~H"""
    <div id={@id} class="oidc-scope-rules">
      <div :for={scope <- @scopes} data-part="rule" id={"#{@id}-#{slug(scope)}"}>
        <div data-part="info">
          <span data-part="label">{scope_label(scope)}</span>
          <span data-part="scope">{scope}</span>
        </div>
        <div data-part="summary">
          <%= case Map.get(@rules, scope) do %>
            <% nil -> %>
              <.badge
                label={dgettext("dashboard", "Any workflow")}
                color="neutral"
                style="light-fill"
                size="small"
              />
            <% rule -> %>
              <span :for={{field, patterns} <- rule_fields(rule)} data-part="field">
                <span data-part="field-label">{field_label(field)}</span>
                <span data-part="patterns">{Enum.join(patterns, ", ")}</span>
              </span>
          <% end %>
        </div>
        <.form
          for={%{}}
          id={"#{@id}-#{slug(scope)}-form"}
          phx-submit="save_oidc_rule"
          data-part="form"
        >
          <.modal
            id={"#{@id}-#{slug(scope)}-modal"}
            title={scope_label(scope)}
            description={
              dgettext(
                "dashboard",
                "OIDC tokens from GitHub Actions can use %{scope} only when every field you fill in matches. Other runs keep read access.",
                scope: scope
              )
            }
            header_size="large"
            on_dismiss="close_oidc_rule_modal"
          >
            <:trigger :let={attrs}>
              <.button
                variant="secondary"
                size="medium"
                label={dgettext("dashboard", "Configure")}
                {attrs}
              />
            </:trigger>
            <.line_divider />
            <input type="hidden" name="scope" value={scope} />
            <.text_input
              id={"#{@id}-#{slug(scope)}-refs"}
              type="basic"
              name="refs"
              value={patterns_value(@rules, scope, :refs)}
              label={dgettext("dashboard", "Branches and tags")}
              placeholder="refs/heads/main, refs/tags/v*"
              hint={dgettext("dashboard", "Matched against the ref claim.")}
              error={Map.get(@errors, scope)}
            />
            <.text_input
              id={"#{@id}-#{slug(scope)}-job-workflow-refs"}
              type="basic"
              name="job_workflow_refs"
              value={patterns_value(@rules, scope, :job_workflow_refs)}
              label={dgettext("dashboard", "Workflows")}
              placeholder="org/repo/.github/workflows/release.yml@refs/heads/main"
              hint={
                dgettext(
                  "dashboard",
                  "Matched against the job_workflow_ref claim. Use ** to match any ref."
                )
              }
            />
            <.text_input
              id={"#{@id}-#{slug(scope)}-environments"}
              type="basic"
              name="environments"
              value={patterns_value(@rules, scope, :environments)}
              label={dgettext("dashboard", "Environments")}
              placeholder="release"
              hint={
                dgettext(
                  "dashboard",
                  "Matched against the environment claim. Separate patterns with commas; * matches within a path segment."
                )
              }
            />
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
      </div>
    </div>
    """
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
        |> Phoenix.Component.assign(:oidc_rules, rules_by_scope(callbacks.list_rules.()))
        |> Phoenix.Component.assign(:oidc_rule_errors, %{})
        |> push_event("close-modal", %{id: "#{callbacks.id}-#{slug(scope)}-modal"})
        |> put_flash(:info, dgettext("dashboard", "OIDC rule saved."))

      {:error, %Ecto.Changeset{} = changeset} ->
        Phoenix.Component.assign(
          socket,
          :oidc_rule_errors,
          Map.put(socket.assigns.oidc_rule_errors, scope, changeset_error(changeset))
        )
    end
  end

  def handle_rule_event("delete_oidc_rule", %{"scope" => scope}, socket, callbacks) do
    :ok = callbacks.delete_rule.(scope)

    socket
    |> Phoenix.Component.assign(:oidc_rules, rules_by_scope(callbacks.list_rules.()))
    |> Phoenix.Component.assign(:oidc_rule_errors, %{})
    |> push_event("close-modal", %{id: "#{callbacks.id}-#{slug(scope)}-modal"})
    |> put_flash(:info, dgettext("dashboard", "OIDC rule removed."))
  end

  def handle_rule_event("close_oidc_rule_modal", params, socket, callbacks) do
    socket = Phoenix.Component.assign(socket, :oidc_rule_errors, %{})

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

  defp rule_fields(rule) do
    Enum.reject(
      [refs: rule.refs, job_workflow_refs: rule.job_workflow_refs, environments: rule.environments],
      fn {_field, patterns} -> patterns == [] end
    )
  end

  defp patterns_value(rules, scope, field) do
    case Map.get(rules, scope) do
      nil -> ""
      rule -> Enum.join(Map.fetch!(rule, field), ", ")
    end
  end

  defp slug(scope), do: String.replace(scope, ":", "-")

  defp field_label(:refs), do: dgettext("dashboard", "Branches and tags")
  defp field_label(:job_workflow_refs), do: dgettext("dashboard", "Workflows")
  defp field_label(:environments), do: dgettext("dashboard", "Environments")

  defp scope_label("project:cache:write"), do: dgettext("dashboard", "Cache uploads")
  defp scope_label("project:previews:write"), do: dgettext("dashboard", "Preview uploads")
  defp scope_label("project:bundles:write"), do: dgettext("dashboard", "Bundle uploads")
  defp scope_label("project:tests:write"), do: dgettext("dashboard", "Test results")
  defp scope_label("project:builds:write"), do: dgettext("dashboard", "Build insights")
  defp scope_label("project:runs:write"), do: dgettext("dashboard", "Command runs")
  defp scope_label("account:cache:write"), do: dgettext("dashboard", "Account-wide cache uploads")
  defp scope_label(scope), do: scope
end
