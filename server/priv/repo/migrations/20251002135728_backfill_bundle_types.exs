defmodule Tuist.Repo.Migrations.BackfillBundleTypes do
  use Ecto.Migration
  import Ecto.Query

  def up do
    # Update bundles with download_size to type :ipa (0)
    from(b in "bundles", where: not is_nil(b.download_size), update: [set: [type: 0]])
    |> Tuist.Repo.update_all([])
  end

  def down do
    # No-op: we can't reliably reverse this migration
  end
end
