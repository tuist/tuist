defmodule Tuist.SCIM.Workers.AttachmentNotifierWorker do
  @moduledoc """
  Notifies a Tuist user that they were attached to an organization by that
  organization's SCIM provisioning.

  Enqueued from inside the `Tuist.SCIM.provision_user/2` transaction so the
  job is only delivered if the attachment actually commits — rollbacks drop
  the job, preventing emails about attachments that never happened.
  """
  use Oban.Worker, queue: :default, max_attempts: 5

  alias Tuist.Accounts.Organization
  alias Tuist.Accounts.User
  alias Tuist.Accounts.UserNotifier
  alias Tuist.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "organization_id" => organization_id}}) do
    user = Repo.get!(User, user_id)
    organization = Organization |> Repo.get!(organization_id) |> Repo.preload(:account)
    UserNotifier.deliver_scim_organization_attachment(user, organization)
    :ok
  end
end
