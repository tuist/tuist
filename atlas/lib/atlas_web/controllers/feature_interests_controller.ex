defmodule AtlasWeb.FeatureInterestsController do
  use AtlasWeb, :controller

  alias Atlas.Accounts
  alias Atlas.Audit
  alias Atlas.MCP.Serializers.FeatureInterests

  def index(conn, _params) do
    interests = Accounts.list_feature_interests()

    json(conn, %{
      feature_interests: Enum.map(interests, &FeatureInterests.feature_interest/1),
      count: length(interests)
    })
  end

  def create(conn, params) do
    result =
      Audit.with_context(%{actor: conn.assigns.current_user, interface: "api"}, fn ->
        Accounts.create_feature_interest(Map.take(params, ["title", "status"]), conn.assigns.current_user)
      end)

    case result do
      {:ok, interest} ->
        conn
        |> put_status(:created)
        |> json(%{feature_interest: FeatureInterests.feature_interest(interest)})

      {:error, changeset} ->
        validation_error(conn, changeset)
    end
  end

  def show(conn, %{"id" => id}) do
    case Accounts.get_feature_interest(id) do
      nil -> not_found(conn, "Feature interest not found.")
      interest -> json(conn, %{feature_interest: FeatureInterests.feature_interest_detail(interest)})
    end
  end

  def list_for_account(conn, %{"account_id" => account_id}) do
    case Accounts.get_account(account_id) do
      nil ->
        not_found(conn, "Account not found.")

      account ->
        interests = Accounts.list_feature_interests_for_account(account)

        json(conn, %{
          feature_interests: Enum.map(interests, &FeatureInterests.account_interest(List.first(&1.accounts))),
          count: length(interests)
        })
    end
  end

  def record_from_event(conn, %{"account_id" => account_id, "event_id" => event_id} = params) do
    with account when not is_nil(account) <- Accounts.get_account(account_id),
         {:ok, event} <- Accounts.get_account_event(account, event_id) do
      result =
        Audit.with_context(%{actor: conn.assigns.current_user, interface: "api"}, fn ->
          Accounts.record_feature_interest_from_event(
            event,
            interest_attrs(params),
            conn.assigns.current_user
          )
        end)

      case result do
        {:ok, %{interest: interest, account_interest: account_interest}} ->
          account_interest = Accounts.get_feature_interest_account(account_interest.id)

          conn
          |> put_status(:created)
          |> json(%{
            feature_interest: FeatureInterests.feature_interest(interest),
            account_interest: FeatureInterests.account_interest(account_interest)
          })

        {:error, :account_required} ->
          validation_error(conn, %{account: ["is required"]})

        {:error, changeset} ->
          validation_error(conn, changeset)
      end
    else
      nil -> not_found(conn, "Account not found.")
      {:error, :event_not_found} -> not_found(conn, "Timeline event not found for this account.")
    end
  end

  def update_account_context(conn, %{"id" => id} = params) do
    case Accounts.get_feature_interest_account(id) do
      nil ->
        not_found(conn, "Feature interest record not found.")

      interest_account ->
        result =
          Audit.with_context(%{actor: conn.assigns.current_user, interface: "api"}, fn ->
            Accounts.update_feature_interest_notes(
              interest_account,
              context_attrs(params),
              conn.assigns.current_user
            )
          end)

        case result do
          {:ok, updated_interest_account} ->
            account_interest = Accounts.get_feature_interest_account(updated_interest_account.id)
            json(conn, %{account_interest: FeatureInterests.account_interest(account_interest)})

          {:error, :not_found} ->
            not_found(conn, "Feature interest record not found.")

          {:error, changeset} ->
            validation_error(conn, changeset)
        end
    end
  end

  defp not_found(conn, message) do
    conn
    |> put_status(:not_found)
    |> json(%{error: message})
  end

  defp validation_error(conn, %Ecto.Changeset{} = changeset) do
    validation_error(conn, Ecto.Changeset.traverse_errors(changeset, &error_message/1))
  end

  defp validation_error(conn, errors) when is_map(errors) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: errors})
  end

  defp error_message({message, options}) do
    Enum.reduce(options, message, fn {key, value}, message ->
      String.replace(message, "%{#{key}}", to_string(value))
    end)
  end

  defp interest_attrs(params) do
    params
    |> Map.take(["title", "summary", "notes"])
    |> Map.merge(context_attrs(params))
  end

  defp context_attrs(%{"context" => context}), do: %{"notes" => context}
  defp context_attrs(params), do: Map.take(params, ["notes"])
end
