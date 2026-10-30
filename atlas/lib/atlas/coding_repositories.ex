defmodule Atlas.CodingRepositories do
  @moduledoc "Personal GitHub installation catalogues and defaults, separate from execution authority."

  alias Atlas.Audit
  alias Atlas.Connections
  alias Atlas.Environments
  alias Atlas.Integrations.GitHubAPI
  alias Atlas.Repo
  alias Atlas.Users.User

  def settings(%User{id: id}) do
    Map.merge(%{"installation_id" => nil, "default_repository" => nil}, Repo.get!(User, id).coding_preferences)
  end

  def catalog(user, installation_id \\ :saved) do
    preferences = settings(user)
    selected = if installation_id == :saved, do: preferences["installation_id"], else: installation_id

    with true <- is_nil(selected) or installation_id?(selected),
         {:ok, token} <- Connections.access_token(user, "github"),
         {:ok, installations} <- GitHubAPI.accessible_installations(token),
         true <- is_nil(selected) or Enum.any?(installations, &(&1.id == selected)),
         {:ok, repositories} <- repositories(token, selected) do
      Audit.record(
        "coding_repositories.listed",
        %{
          target_type: "user",
          target_id: user.id,
          metadata: %{repository_count: length(repositories), dashboard_path: "/settings/coding"}
        },
        actor: user
      )

      {:ok, %{settings: preferences, installations: installations, repositories: repositories}}
    else
      false -> {:error, :installation_unavailable}
      {:error, reason} when reason in [:not_connected, :needs_authorization] -> {:error, :github_connection_required}
      {:error, reason} -> {:error, reason}
    end
  end

  def update(user, params) do
    with true <- Environments.exact_keys?(params, ~w(installation_id default_repository)),
         installation = params["installation_id"],
         repository = params["default_repository"],
         true <- is_nil(installation) or installation_id?(installation),
         true <- is_nil(repository) or (not is_nil(installation) and repository?(repository)),
         :ok <- validate_default(user, installation, repository) do
      preferences = %{
        "installation_id" => installation,
        "default_repository" => repository && String.downcase(repository)
      }

      Repo.transaction(fn ->
        User |> Repo.get!(user.id) |> Ecto.Changeset.change(coding_preferences: preferences) |> Repo.update!()

        Audit.record(
          "user.coding_preferences_updated",
          %{
            target_type: "user",
            target_id: user.id,
            metadata: %{dashboard_path: "/settings/coding"}
          },
          actor: user
        )

        preferences
      end)
    else
      false -> {:error, :invalid_params}
      error -> error
    end
  end

  def authorize_repository(_user, nil), do: {:ok, nil}

  def authorize_repository(user, repository) do
    with true <- repository?(repository),
         {:ok, catalog} <- catalog(user),
         name = String.downcase(repository),
         true <- Enum.any?(catalog.repositories, &(&1.full_name == name)) do
      {:ok, name}
    else
      false -> {:error, :repository_unavailable}
      error -> error
    end
  end

  def repository?(name) when is_binary(name),
    do: String.valid?(name) and Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9-]{0,38}\/[a-zA-Z0-9_.-]{1,100}\z/, name)

  def repository?(_), do: false

  def installation_id?(id) when is_binary(id), do: Regex.match?(~r/\A[1-9][0-9]{0,19}\z/, id)
  def installation_id?(_), do: false

  def allowed_context?(%{assigns: %{audit_interface: "slack"}}), do: false
  def allowed_context?(%{assigns: %{mcp_claims: %{"slack_agent" => _}}}), do: false
  def allowed_context?(_), do: true

  def error_message(:github_connection_required),
    do: "Connect your GitHub account in Connections to choose repositories."

  def error_message(:installation_unavailable),
    do: "This GitHub App installation is no longer available. Choose another installation."

  def error_message(:repository_unavailable),
    do: "This repository is not available through your selected GitHub installation."

  def error_message(:github_catalog_limit),
    do: "This GitHub catalogue exceeds the supported size. Contact your administrator."

  def error_message(_), do: "Could not refresh GitHub repositories. Try again; your selection has not changed."

  def settings_schema do
    %{
      "type" => "object",
      "properties" => %{
        "installation_id" => %{"type" => ["string", "null"], "pattern" => "^[1-9][0-9]{0,19}$"},
        "default_repository" => %{"type" => ["string", "null"], "maxLength" => 140}
      },
      "required" => ~w(installation_id default_repository),
      "additionalProperties" => false
    }
  end

  def catalog_schema do
    %{
      "type" => "object",
      "properties" => %{
        "settings" => settings_schema(),
        "installations" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{"id" => %{"type" => "string"}, "name" => %{"type" => "string"}},
            "required" => ~w(id name),
            "additionalProperties" => false
          }
        },
        "repositories" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{"full_name" => %{"type" => "string"}},
            "required" => ["full_name"],
            "additionalProperties" => false
          }
        }
      },
      "required" => ~w(settings installations repositories),
      "additionalProperties" => false
    }
  end

  defp repositories(_token, nil), do: {:ok, []}
  defp repositories(token, id), do: GitHubAPI.accessible_repositories(token, id)

  defp validate_default(_user, nil, nil), do: :ok

  defp validate_default(user, installation, repository) do
    with {:ok, catalog} <- catalog(user, installation) do
      if is_nil(repository) or Enum.any?(catalog.repositories, &(&1.full_name == String.downcase(repository))),
        do: :ok,
        else: {:error, :repository_unavailable}
    end
  end
end
