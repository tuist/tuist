defmodule Tuist.Automations do
  @moduledoc false
  import Ecto.Query

  alias Tuist.Automations.Alerts.Alert
  alias Tuist.Automations.AlertRule
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Repo

  def list_alert_rules(project_id) do
    AlertRule
    |> where(project_id: ^project_id)
    |> order_by(asc: :inserted_at)
    |> Repo.all()
  end

  def get_alert_rule(id) do
    case Repo.get(AlertRule, id) do
      nil -> {:error, :not_found}
      alert_rule -> {:ok, alert_rule}
    end
  end

  def create_alert_rule(attrs) do
    %AlertRule{}
    |> AlertRule.changeset(attrs)
    |> Repo.insert()
  end

  def update_alert_rule(%AlertRule{} = alert_rule, attrs) do
    alert_rule
    |> AlertRule.changeset(attrs)
    |> Repo.update()
  end

  def delete_alert_rule(%AlertRule{} = alert_rule) do
    Repo.delete(alert_rule)
  end

  @doc """
  Returns currently active alerts for an alert rule (latest status = "triggered").
  Uses argMax to find the most recent status per test_case_id from the append-only log.
  """
  def list_active_alerts(alert_rule_id) do
    ClickHouseRepo.all(
      from(a in Alert,
        where: a.alert_rule_id == ^alert_rule_id,
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
end
