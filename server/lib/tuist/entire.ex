defmodule Tuist.Entire do
  @moduledoc """
  Account-scoped Entire plugin installations and durable webhook delivery.
  Independent of Tuist's CI scheduler and executor.
  """

  import Ecto.Query

  alias Tuist.Entire.Client
  alias Tuist.Entire.Delivery
  alias Tuist.Entire.Installation
  alias Tuist.Entire.InstallRequest
  alias Tuist.Entire.Workers.DeliveryWorker
  alias Tuist.EntireTrails
  alias Tuist.Repo

  def begin_install(account) do
    state = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    now = DateTime.utc_now(:second)
    Repo.delete_all(from request in InstallRequest, where: request.expires_at <= ^now)

    with {:ok, _} <-
           Repo.insert(%InstallRequest{state: state, account_id: account.id, expires_at: DateTime.add(now, 600)}) do
      {:ok, state}
    end
  end

  def finish_install(account, state, receipt) do
    with {:ok, claims} <- Client.verify_receipt(receipt, state) do
      Repo.transaction(fn ->
        now = DateTime.utc_now(:second)

        {consumed, _} =
          Repo.delete_all(
            from request in InstallRequest,
              where: request.state == ^state and request.account_id == ^account.id and request.expires_at > ^now
          )

        if consumed != 1, do: Repo.rollback(:invalid_state)

        case Repo.get_by(Installation, remote_id: claims["installation_id"]) do
          nil ->
            %Installation{}
            |> Installation.changeset(%{account_id: account.id, remote_id: claims["installation_id"]})
            |> Repo.insert!()

          %Installation{account_id: account_id} = installation when account_id == account.id ->
            installation

          _ ->
            Repo.rollback(:installation_already_connected)
        end
      end)
    end
  end

  def accept_delivery(delivery, jwt_id) do
    Repo.transaction(fn ->
      {inserted, _} =
        Repo.insert_all(
          Delivery,
          [%{id: delivery["delivery_id"], jwt_id: jwt_id, inserted_at: DateTime.utc_now(:second)}],
          on_conflict: :nothing
        )

      if inserted == 1 do
        delivery
        |> DeliveryWorker.new()
        |> Oban.insert!()
      end
    end)
  end

  def handle_delivery(%{
        "installation_id" => remote_id,
        "event" => %{"type" => "installation." <> action, "payload" => %{"installation" => change}}
      })
      when action in ["deleted", "suspended", "resumed"] do
    fn ->
      installation = Repo.one(from i in Installation, where: i.remote_id == ^remote_id, lock: "FOR UPDATE")

      if installation && is_integer(change["revision"]) && change["revision"] > installation.revision do
        active = action == "resumed"

        installation |> Ecto.Changeset.change(active: active, revision: change["revision"]) |> Repo.update!()
      end
    end
    |> Repo.transaction()
    |> case do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  def handle_delivery(delivery), do: EntireTrails.handle_delivery(delivery)
end
