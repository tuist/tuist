defmodule Tuist.Accounts.OrganizationAI do
  @moduledoc """
  Organization-owned inference routing. Settings expose metadata only; keys
  never leave this server-side context. Callers of `complete/2` must
  authorize the workflow against its owning account before dispatching it.
  Personal subscription credentials are never used as a fallback.
  """

  import Ecto.Query, only: [from: 2]

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.ClaudeLinkedBilling
  alias Tuist.Accounts.Organization
  alias Tuist.Accounts.OrganizationAIConnection
  alias Tuist.Accounts.OrganizationAIDefault
  alias Tuist.Accounts.OrganizationAIModel
  alias Tuist.Authorization
  alias Tuist.FeatureFlags
  alias Tuist.OAuth2.PinnedHTTP
  alias Tuist.OAuth2.SSRFGuard
  alias Tuist.Repo

  @provider_templates [
    %{id: "openai", name: "OpenAI", base_url: "https://api.openai.com/v1"},
    %{id: "fireworks", name: "Fireworks AI", base_url: "https://api.fireworks.ai/inference/v1"},
    %{id: "together", name: "Together AI", base_url: "https://api.together.ai/v1"}
  ]

  def provider_templates, do: @provider_templates

  def settings(user, account) do
    with {:ok, account} <- authorize(user, account) do
      Repo.transaction(fn ->
        # Keep the three metadata reads consistent with concurrent removals.
        Repo.one!(from o in Organization, where: o.id == ^account.organization_id, select: o.id, lock: "FOR SHARE")

        %{
          connections:
            Repo.all(
              from c in OrganizationAIConnection,
                where: c.organization_id == ^account.organization_id,
                order_by: [asc: c.id],
                select: map(c, [:id, :kind, :name, :base_url, :updated_at])
            ),
          models:
            Repo.all(
              from m in OrganizationAIModel,
                where: m.organization_id == ^account.organization_id,
                order_by: [asc: m.id],
                select: map(m, [:id, :name, :connection_id, :model_id, :updated_at])
            ),
          default_model_id:
            Repo.one(
              from d in OrganizationAIDefault, where: d.organization_id == ^account.organization_id, select: d.model_id
            )
        }
      end)
    end
  end

  def save_connection(user, account, attrs) do
    update(user, account, fn org_id ->
      connection =
        if attrs["_id"] in [nil, ""],
          do: %OrganizationAIConnection{organization_id: org_id},
          else: owned!(OrganizationAIConnection, org_id, attrs["_id"])

      # A linked Claude organization is managed through linking, never edited as a key.
      if connection.kind != "api_key", do: Repo.rollback(:not_found)

      connection
      |> OrganizationAIConnection.changeset(attrs)
      |> persist!()
      |> Map.take([:id, :name, :base_url, :updated_at])
    end)
  end

  def save_model(user, account, attrs) do
    update(user, account, fn org_id ->
      model =
        if attrs["_id"] in [nil, ""],
          do: %OrganizationAIModel{organization_id: org_id},
          else: owned!(OrganizationAIModel, org_id, attrs["_id"])

      changeset = OrganizationAIModel.changeset(model, attrs)

      if !(changeset.valid? and
             Repo.exists?(
               from c in OrganizationAIConnection,
                 where: c.id == ^Ecto.Changeset.get_field(changeset, :connection_id) and c.organization_id == ^org_id
             )) do
        Repo.rollback(:invalid_configuration)
      end

      changeset |> persist!() |> Map.take([:id, :name, :connection_id, :model_id, :updated_at])
    end)
  end

  def set_default(user, account, model_id) do
    update(user, account, fn org_id ->
      if model_id in [nil, ""] do
        Repo.delete_all(from d in OrganizationAIDefault, where: d.organization_id == ^org_id)
        nil
      else
        model = owned!(OrganizationAIModel, org_id, model_id)

        default =
          Repo.get_by(OrganizationAIDefault, organization_id: org_id) ||
            %OrganizationAIDefault{organization_id: org_id}

        default |> Ecto.Changeset.change(model_id: model.id) |> persist!()
        model.id
      end
    end)
  end

  @doc """
  Removes a connection. Removing a linked Claude organization first unlinks
  it at Anthropic, so Tuist can no longer bill it, and keeps it when that fails.
  """
  def remove_connection(user, account, id) do
    with {:ok, account} <- authorize(user, account),
         :ok <- unlink_claude(account, id) do
      remove(user, account, OrganizationAIConnection, id)
    end
  end

  def remove_model(user, account, id), do: remove(user, account, OrganizationAIModel, id)

  defp unlink_claude(account, id) do
    with {:ok, id} when is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807 <- Ecto.Type.cast(:id, id),
         true <-
           Repo.exists?(
             from c in OrganizationAIConnection,
               where: c.id == ^id and c.organization_id == ^account.organization_id and c.kind == "claude_linked_billing"
           ),
         profile_id when is_binary(profile_id) <- claude_user_profile_id(account) do
      if ClaudeLinkedBilling.unlink(profile_id) == :ok, do: :ok, else: {:error, :unlink_failed}
    else
      # Other connections, and unknown ids, which removal itself refuses.
      _ -> :ok
    end
  end

  @doc """
  Starts linking the organization's Claude organization for billing. Returns
  the approval page URL and the `state` and PKCE verifier that
  `link_claude/4` needs after the callback.
  """
  def start_claude_link(user, account) do
    with {:ok, account} <- authorize(user, account),
         true <- ClaudeLinkedBilling.configured?() || {:error, :not_configured},
         {:ok, profile_id} <- ensure_claude_user_profile(account) do
      ClaudeLinkedBilling.authorization_request(profile_id)
    end
  end

  @doc "Completes linking with the callback's code and stores the connection as a provider."
  def link_claude(user, account, code, code_verifier) do
    with {:ok, _account} <- authorize(user, account),
         {:ok, connection_id} <- ClaudeLinkedBilling.exchange_code(code, code_verifier) do
      update(user, account, fn org_id ->
        (Repo.get_by(OrganizationAIConnection, organization_id: org_id, kind: "claude_linked_billing") ||
           %OrganizationAIConnection{organization_id: org_id})
        |> OrganizationAIConnection.linked_billing_changeset(connection_id)
        |> persist!()
        |> Map.take([:id, :kind, :name, :updated_at])
      end)
    end
  end

  # Anthropic creates a new profile on every request, so each organization keeps
  # the first one it stores and reuses it for every later link.
  defp ensure_claude_user_profile(account) do
    case claude_user_profile_id(account) do
      nil ->
        with {:ok, profile_id} <-
               ClaudeLinkedBilling.create_user_profile(account.name, "tuist-organization-#{account.organization_id}") do
          Repo.update_all(
            from(o in Organization, where: o.id == ^account.organization_id and is_nil(o.anthropic_user_profile_id)),
            set: [anthropic_user_profile_id: profile_id]
          )

          {:ok, claude_user_profile_id(account)}
        end

      profile_id ->
        {:ok, profile_id}
    end
  end

  defp claude_user_profile_id(account),
    do: Repo.one(from o in Organization, where: o.id == ^account.organization_id, select: o.anthropic_user_profile_id)

  defp remove(user, account, schema, id) do
    update(user, account, fn org_id ->
      schema |> owned!(org_id, id) |> Repo.delete!()
      :ok
    end)
  end

  @doc "Runs an authorized organization workflow through its current route, without retries or provider fallback."
  def complete(%Account{id: id}, messages) when is_list(messages) do
    with %Account{organization_id: org_id} = account when not is_nil(org_id) <- Repo.get(Account, id),
         true <- FeatureFlags.organization_luft_enabled?(account),
         %{} = route <-
           Repo.one(
             from d in OrganizationAIDefault,
               join: m in OrganizationAIModel,
               on: m.id == d.model_id and m.organization_id == d.organization_id,
               join: c in OrganizationAIConnection,
               on: c.id == m.connection_id and c.organization_id == m.organization_id,
               join: o in Organization,
               on: o.id == d.organization_id,
               where: d.organization_id == ^org_id,
               select: %{
                 kind: c.kind,
                 base_url: c.base_url,
                 api_key: c.api_key,
                 model_id: m.model_id,
                 user_profile_id: o.anthropic_user_profile_id
               }
           ) do
      dispatch(route, messages)
    else
      false -> {:error, :disabled}
      _ -> {:error, :not_configured}
    end
  end

  defp dispatch(%{kind: "claude_linked_billing", user_profile_id: profile_id} = route, messages)
       when is_binary(profile_id) do
    case ClaudeLinkedBilling.billing(profile_id) do
      {:ok, billing} -> request(billing.url, billing.headers, billing.body, route.model_id, messages)
      {:error, _} -> {:error, :provider_unavailable}
    end
  end

  defp dispatch(%{kind: "api_key"} = route, messages) do
    request(
      route.base_url <> "/chat/completions",
      [{"authorization", "Bearer " <> route.api_key}],
      %{},
      route.model_id,
      messages
    )
  end

  defp dispatch(_route, _messages), do: {:error, :not_configured}

  defp request(url, headers, body, model_id, messages) do
    # Resolve again on every dispatch and connect only to the validated address.
    # The unpooled client preserves TLS verification and never redirects/retries.
    with {:ok, url, hostname} <- SSRFGuard.pin(url),
         {:ok, %{body: response}} <-
           PinnedHTTP.request("POST", url,
             headers: headers ++ [{"content-type", "application/json"}],
             body: JSON.encode!(Map.merge(body, %{model: model_id, messages: messages, stream: false})),
             accept_status: 200,
             connect_options: Keyword.put(SSRFGuard.connect_options(hostname), :timeout, 5_000),
             receive_timeout: 60_000,
             total_timeout: 60_000,
             max_body_bytes: 4 * 1024 * 1024
           ),
         {:ok, %{"choices" => choices} = body} when is_list(choices) <- JSON.decode(response) do
      {:ok, body}
    else
      {:error, {:unexpected_status, status}} -> {:error, {:provider_error, status}}
      _ -> {:error, :provider_unavailable}
    end
  end

  defp authorize(user, %Account{id: id}) do
    with %Account{organization_id: org_id} = account when not is_nil(org_id) <- Repo.get(Account, id),
         true <- FeatureFlags.organization_luft_enabled?(account),
         :ok <- Authorization.authorize(:account_update, user, account) do
      {:ok, account}
    else
      false -> {:error, :disabled}
      _ -> {:error, :forbidden}
    end
  end

  defp lock_organization(account),
    do: Repo.one!(from o in Organization, where: o.id == ^account.organization_id, select: o.id, lock: "FOR UPDATE")

  defp update(user, account, operation) do
    with {:ok, account} <- authorize(user, account) do
      # All configuration mutations share the same cross-replica lock, including
      # selecting a default while another request removes its model/connection.
      Repo.transaction(fn ->
        lock_organization(account)
        operation.(account.organization_id)
      end)
    end
  end

  defp owned!(schema, org_id, id) do
    with {:ok, id} when is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807 <- Ecto.Type.cast(:id, id),
         record when not is_nil(record) <- Repo.get_by(schema, id: id, organization_id: org_id) do
      record
    else
      _ -> Repo.rollback(:not_found)
    end
  end

  defp persist!(changeset) do
    case Repo.insert_or_update(changeset) do
      {:ok, record} -> record
      {:error, _} -> Repo.rollback(:invalid_configuration)
    end
  end
end
