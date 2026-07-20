defmodule Tuist.Repo.Migrations.ResetRunnerVolumeHeadsForContentAddressedKeys do
  use Ecto.Migration

  # The runner cache-volume master object key changed from a single mutable
  # `runner-volume-masters/<account>/tuist-cache.zip` to content-addressed,
  # immutable `runner-volume-masters/<account>/tuist-cache/<digest>.image`.
  #
  # Existing HEAD rows carry a digest that, under the new scheme, dispatch
  # interpolates into a `<digest>.image` key that was NEVER written (the object
  # only ever existed at the old `.zip` key). A behind host would fetch that key,
  # get a 404, and keep its local master — harmless but noisy. Clear the rows so
  # dispatch hands out no download URL until the first cache-changing job under
  # the new scheme re-establishes a valid, content-addressed HEAD. This only
  # resets cross-host convergence pointer state (reconstructed on the next
  # promote); on-disk local masters are untouched. The one leftover `.zip` object
  # per account is swept by the existing account-deletion prefix cleanup.
  def up do
    execute("DELETE FROM runner_volume_heads")
  end

  # Irreversible by design: the pre-change digests referenced a key format that no
  # longer exists, so there is nothing correct to restore.
  def down, do: :ok
end
