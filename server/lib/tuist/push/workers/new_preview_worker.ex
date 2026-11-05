defmodule Tuist.Push.Workers.NewPreviewWorker do
  @moduledoc """
  Fans a new preview out to the devices of the project account's members who
  want `new_preview` notifications for the project, one `DeliveryWorker` job per
  device. Devices on a platform whose provider isn't configured are skipped. Enqueued when a preview's build finishes uploading; unique per preview
  for a day, so a preview with several builds notifies once.
  """

  use Oban.Worker,
    queue: :push,
    max_attempts: 3,
    unique: [keys: [:preview_id], period: 24 * 60 * 60, states: :successful]

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.Role
  alias Tuist.Accounts.UserRole
  alias Tuist.AppBuilds.Preview
  alias Tuist.Notifications
  alias Tuist.Push
  alias Tuist.Push.APNs
  alias Tuist.Push.FCM
  alias Tuist.Push.Workers.DeliveryWorker
  alias Tuist.Repo

  # A build uploaded to a preview older than this isn't a new preview.
  @max_age_seconds 24 * 60 * 60

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"preview_id" => preview_id}}) do
    with %Preview{} = preview <- Preview |> Repo.get(preview_id) |> Repo.preload(project: :account),
         true <- DateTime.diff(DateTime.utc_now(), preview.inserted_at) < @max_age_seconds do
      payloads = payloads(preview)

      preview.project.account
      |> member_ids()
      |> Enum.filter(&Notifications.notify?(&1, "new_preview", preview.project_id))
      |> Enum.flat_map(&Push.live_installations/1)
      |> Enum.filter(&Map.has_key?(payloads, &1.platform))
      |> Enum.map(&DeliveryWorker.new(%{"registration_id" => &1.id, "payload" => Map.fetch!(payloads, &1.platform)}))
      |> Oban.insert_all()
    end

    :ok
  end

  defp member_ids(%Account{user_id: user_id}) when is_integer(user_id), do: [user_id]

  defp member_ids(%Account{organization_id: organization_id}) do
    UserRole
    |> join(:inner, [ur], r in Role, on: ur.role_id == r.id)
    |> where([_ur, r], r.resource_type == "Organization" and r.resource_id == ^organization_id)
    |> distinct(true)
    |> select([ur], ur.user_id)
    |> Repo.all()
  end

  # The payload for each platform whose provider is configured on this server.
  defp payloads(%Preview{project: project} = preview) do
    full_handle = "#{project.account.name}/#{project.name}"
    title = preview.display_name || project.name
    version = if preview.version in [nil, ""], do: "A new preview", else: "Version #{preview.version}"
    body = "#{version} is ready to install."

    ids = %{
      "preview_id" => preview.id,
      "account_handle" => project.account.name,
      "project_handle" => project.name
    }

    ios =
      Map.put(ids, "aps", %{
        "alert" => %{"title" => title, "subtitle" => full_handle, "body" => body},
        "sound" => "default",
        "thread-id" => full_handle
      })

    # Android has no subtitle line, so the project goes into the title.
    android = Map.merge(ids, %{"title" => "#{title} · #{full_handle}", "body" => body})

    %{}
    |> then(&if(APNs.configured?(), do: Map.put(&1, "ios", ios), else: &1))
    |> then(&if(FCM.configured?(), do: Map.put(&1, "android", android), else: &1))
  end
end
