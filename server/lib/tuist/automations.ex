defmodule Tuist.Automations do
  @moduledoc false
  import Ecto.Query

  alias Tuist.Automations.Alerts.Alert
  alias Tuist.Automations.Automation
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Repo

  def list_automations(project_id) do
    Automation
    |> where(project_id: ^project_id)
    |> order_by(asc: :inserted_at)
    |> Repo.all()
  end

  def get_automation(id) do
    case Repo.get(Automation, id) do
      nil -> {:error, :not_found}
      automation -> {:ok, automation}
    end
  end

  def create_automation(attrs) do
    %Automation{}
    |> Automation.changeset(attrs)
    |> Repo.insert()
  end

  def update_automation(%Automation{} = automation, attrs) do
    automation
    |> Automation.changeset(attrs)
    |> Repo.update()
  end

  def delete_automation(%Automation{} = automation) do
    Repo.delete(automation)
  end

  # --- Alerts ---

  @doc """
  Returns currently active alerts for an automation (latest status = "triggered").
  Uses argMax to find the most recent status per test_case_id from the append-only log.
  """
  def list_active_alerts(automation_id) do
    ClickHouseRepo.all(
      from(a in Alert,
        where: a.automation_id == ^automation_id,
        group_by: a.test_case_id,
        having: fragment("argMax(?, ?) = 'triggered'", a.status, a.inserted_at),
        select: %{
          test_case_id: a.test_case_id,
          triggered_at: fragment("argMax(?, ?)", a.triggered_at, a.inserted_at)
        }
      )
    )
  end

  @doc """
  Appends an alert event to the log.
  """
  def create_alert(attrs) do
    now = NaiveDateTime.utc_now()

    record =
      attrs
      |> Map.put_new(:id, UUIDv7.generate())
      |> Map.put_new(:inserted_at, now)

    IngestRepo.insert_all(Alert, [record])
    :ok
  end

  @doc """
  Appends a recovery event to the alert log.
  """
  def resolve_alert(automation_id, test_case_id) do
    create_alert(%{
      automation_id: automation_id,
      test_case_id: test_case_id,
      status: "recovered",
      triggered_at: NaiveDateTime.utc_now(),
      recovered_at: NaiveDateTime.utc_now()
    })
  end
end
