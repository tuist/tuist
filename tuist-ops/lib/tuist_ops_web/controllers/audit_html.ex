defmodule TuistOpsWeb.AuditHTML do
  @moduledoc """
  The audit trail page: a tab menu switching between the cluster-access
  and customer-project-access sections, each a full paginated table.
  """
  use TuistOpsWeb, :html

  attr :section, :string, required: true
  attr :requests, :list, required: true
  attr :page, :integer, required: true
  attr :total_pages, :integer, required: true

  def index(assigns) do
    ~H"""
    <div class="ops-page__header">
      <h1 class="ops-page__title">Audit trail</h1>
      <p class="ops-page__subtitle">
        Cluster elevations and customer project-access requests, newest first.
      </p>
    </div>

    <.tab_menu_horizontal>
      <.tab_menu_horizontal_item
        label="Cluster access"
        patch={~p"/audit?section=cluster"}
        selected={@section == "cluster"}
      />
      <.tab_menu_horizontal_item
        label="Customer project access"
        patch={~p"/audit?section=projects"}
        selected={@section == "projects"}
      />
    </.tab_menu_horizontal>

    <div class="ops-tabpanel">
      <%= case @section do %>
        <% "projects" -> %>
          <.card icon="building" title="Access requests">
            <.card_section>
              <.table id="project-access" rows={@requests}>
                <:col :let={r} label="Operator"><.text_cell label={r.requester_email} /></:col>
                <:col :let={r} label="Customer"><.text_cell label={r.account_handle} /></:col>
                <:col :let={r} label="Tier"><.text_cell label={r.tier} /></:col>
                <:col :let={r} label="Reason"><.text_cell label={r.reason} /></:col>
                <:col :let={r} label="Status">
                  <.status_badge_cell status={variant(r.status)} label={humanize(r.status)} />
                </:col>
                <:col :let={r} label="Approver"><.text_cell label={r.approver_email || "—"} /></:col>
                <:col :let={r} label="Requested"><.text_cell label={fmt(r.inserted_at)} /></:col>
                <:empty_state>
                  <.table_empty_state
                    icon="building"
                    title="No project-access requests"
                    subtitle="Operator access requests will show up here once submitted."
                  />
                </:empty_state>
              </.table>

              <.pagination_group
                :if={@total_pages > 1}
                current_page={@page}
                number_of_pages={@total_pages}
                page_patch={fn page -> ~p"/audit?section=projects&page=#{page}" end}
              />
            </.card_section>
          </.card>
        <% _cluster -> %>
          <.card icon="server" title="JIT elevations">
            <.card_section>
              <.table id="cluster-access" rows={@requests}>
                <:col :let={r} label="Operator"><.text_cell label={r.requester_email} /></:col>
                <:col :let={r} label="Environment">
                  <.text_cell label={cluster_env(r.target_group)} />
                </:col>
                <:col :let={r} label="Intent"><.text_cell label={r.intent} /></:col>
                <:col :let={r} label="Status">
                  <.status_badge_cell status={variant(r.status)} label={humanize(r.status)} />
                </:col>
                <:col :let={r} label="Approver"><.text_cell label={r.approver_email || "—"} /></:col>
                <:col :let={r} label="Requested"><.text_cell label={fmt(r.inserted_at)} /></:col>
                <:empty_state>
                  <.table_empty_state
                    icon="server"
                    title="No cluster elevations"
                    subtitle="JIT elevations will show up here once requested."
                  />
                </:empty_state>
              </.table>

              <.pagination_group
                :if={@total_pages > 1}
                current_page={@page}
                number_of_pages={@total_pages}
                page_patch={fn page -> ~p"/audit?section=cluster&page=#{page}" end}
              />
            </.card_section>
          </.card>
      <% end %>
    </div>
    """
  end

  defp cluster_env("group:tuist-" <> rest), do: String.replace_suffix(rest, "-write", "")
  defp cluster_env(other), do: other

  defp humanize(status) when is_binary(status),
    do: status |> String.replace("_", " ") |> capitalize()

  defp humanize(_), do: "—"

  defp capitalize(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest
  defp capitalize(other), do: other

  defp variant(status) when status in ~w(approved active), do: "success"
  defp variant(status) when status in ~w(denied expired failed revert_failed), do: "error"
  defp variant("pending"), do: "warning"
  defp variant(status) when status in ~w(reverting in_progress), do: "in_progress"
  defp variant(status) when status in ~w(reverted cancelled), do: "disabled"
  defp variant(_), do: "attention"

  defp fmt(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
  defp fmt(_), do: "—"
end
