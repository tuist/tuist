defmodule Tuist.Repo.Migrations.AddReportBundleTagToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :report_bundle_tag, :string
    end
  end
end
