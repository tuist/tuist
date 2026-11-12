defmodule PulseWeb.PrometheusLimit do
  @moduledoc false

  @warning "results truncated due to limit"

  def parse(value) when value in [nil, ""], do: {:ok, 0}

  def parse(value) when is_binary(value) and byte_size(value) <= 20 do
    with true <- Regex.match?(~r/\A[+-]?[0-9]+\z/, value),
         {limit, ""} when limit in 0..9_223_372_036_854_775_807 <- Integer.parse(value) do
      {:ok, limit}
    else
      _ -> invalid_limit()
    end
  end

  def parse(_value), do: invalid_limit()

  defp invalid_limit,
    do: {:error, {:invalid_parameter, ~s(invalid parameter "limit": limit must be a non-negative integer)}}

  # Only explicit HTTP result limits truncate. Evaluation and discovery must
  # still finish within their ordinary budgets; no limit turns an incomplete
  # or failed scan into a successful partial response.
  def response(%{"data" => data} = response, limit) when is_list(data) and limit > 0 do
    if length(data) > limit,
      do: response |> Map.put("data", Enum.take(data, limit)) |> warn(),
      else: response
  end

  def response(%{"data" => %{"resultType" => type, "result" => result}} = response, limit)
      when type in ["vector", "matrix"] and limit > 0 do
    if length(result) > limit,
      do: response |> put_in(["data", "result"], Enum.take(result, limit)) |> warn(),
      else: response
  end

  def response(response, _limit), do: response

  defp warn(response), do: Map.update(response, "warnings", [@warning], &Enum.uniq(&1 ++ [@warning]))
end
