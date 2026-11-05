defmodule Pulse.Alerting.Importer do
  @moduledoc "Lossless Grafana dry-run import. Representability is not executability or migration approval."
  alias Pulse.Alerting.Principal
  alias Pulse.Alerting.Rule

  def preview(definitions) when is_list(definitions) and length(definitions) <= 1000 do
    ids = Enum.map(definitions, fn original -> if is_map(original), do: original["uid"] end)

    if Enum.any?(ids, &is_nil/1) or length(Enum.uniq(ids)) != length(ids) do
      {:error, :duplicate_rule_id}
    else
      Enum.reduce_while(definitions, {:ok, []}, &report/2)
    end
  end

  def preview(_), do: {:error, :invalid_import}

  defp report(original, {:ok, reports}) do
    input = %{"kind" => "grafana", "original" => original, "enabled" => false}

    with {:ok, rule} <- Rule.validate(input), true <- Principal.valid_id?(original["uid"]) do
      report = %{
        "id" => original["uid"],
        "rule" => rule,
        "representable" => true,
        "executable" => false,
        "migrated" => false,
        "kind" => if(is_map(original["record"]), do: "recording", else: "alert"),
        "blockers" => ["grafana_execution_not_implemented"]
      }

      {:cont, {:ok, reports ++ [report]}}
    else
      _ -> {:halt, {:error, :invalid_import}}
    end
  end
end
