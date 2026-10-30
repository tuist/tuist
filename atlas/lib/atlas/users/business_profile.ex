defmodule Atlas.Users.BusinessProfile do
  @moduledoc "Explicit, shared routing metadata; never the caller's private self-description."
  alias Atlas.Automations.Contract
  alias Atlas.Repo
  alias Atlas.Users.User

  def schema do
    %{
      "type" => "object",
      "properties" => %{
        "enabled" => %{"type" => "boolean"},
        "role" => %{"type" => "string", "maxLength" => 100, "pattern" => "^[^\\x00]*$"},
        "expertise" => tags(100),
        "responsibilities" => tags(200)
      },
      "required" => ~w(enabled role expertise responsibilities),
      "additionalProperties" => false
    }
  end

  # A shared Slack operator is not the person consenting to routing.
  def allowed_context?(%{assigns: %{audit_interface: "slack"}}), do: false
  def allowed_context?(%{assigns: %{mcp_claims: %{"slack_agent" => _}}}), do: false
  def allowed_context?(_), do: true

  def get(%User{id: id}) do
    case Repo.get(User, id) do
      nil ->
        {:error, :not_found}

      user ->
        {:ok,
         Map.merge(
           %{"enabled" => false, "role" => "", "expertise" => [], "responsibilities" => []},
           user.business_profile
         )}
    end
  end

  def update(%User{id: id} = actor, attrs, opts \\ []) do
    with :ok <- Contract.validate(schema(), attrs),
         %User{} = user <- Repo.get(User, id) do
      Repo.transaction(fn ->
        user |> Ecto.Changeset.change(business_profile: attrs) |> Repo.update!()

        Atlas.Audit.record("user.business_profile_updated", %{target_type: "user", target_id: id},
          actor: actor,
          interface: Keyword.get(opts, :interface, "mcp")
        )

        attrs
      end)
    else
      _ -> {:error, :invalid_params}
    end
  end

  defp tags(max),
    do: %{
      "type" => "array",
      "items" => %{"type" => "string", "minLength" => 1, "maxLength" => max, "pattern" => "^[^\\x00]+$"},
      "maxItems" => 20,
      "uniqueItems" => true
    }
end
