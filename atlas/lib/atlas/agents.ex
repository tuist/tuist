defmodule Atlas.Agents do
  @moduledoc """
  Admin-only agent identity management.

  Identity writes remain dashboard-only because they grant Slack routing,
  service-user, memory, and tool access. External agents should consume the
  resulting behavior through audited Slack and tool activity instead of mutating
  this configuration directly.
  """

  import Ecto.Query

  alias Atlas.Agents.Identity
  alias Atlas.Audit
  alias Atlas.Repo

  def list_identities do
    Identity
    |> order_by([identity], desc: identity.priority, asc: identity.key)
    |> Repo.all()
  end

  def get_identity(id) when is_binary(id), do: Repo.get(Identity, id)

  def create_identity(attrs) do
    %Identity{}
    |> Identity.changeset(attrs)
    |> Repo.insert()
    |> record_identity_change("agent_identity.created")
  end

  def update_identity(%Identity{} = identity, attrs) do
    identity
    |> Identity.changeset(attrs)
    |> Repo.update()
    |> record_identity_change("agent_identity.updated")
  end

  def delete_identity(%Identity{} = identity) do
    identity
    |> Repo.delete()
    |> record_identity_change("agent_identity.deleted")
  end

  defp record_identity_change({:ok, %Identity{} = identity} = result, action) do
    Audit.record(action, %{
      target_type: "agent_identity",
      target_id: identity.id,
      target_label: identity.display_name,
      metadata: %{
        "identity_key" => identity.key,
        "bindings" => identity.bindings,
        "tool_groups" => identity.tool_groups,
        "dashboard_path" => "/admin/identities"
      }
    })

    result
  end

  defp record_identity_change(result, _action), do: result
end
