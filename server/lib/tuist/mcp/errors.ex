defmodule Tuist.MCP.Errors do
  @moduledoc false

  @invalid_request -32_600
  @method_not_found -32_601
  @invalid_params -32_602
  @rate_limited -32_603

  def invalid_request(message), do: {:error, @invalid_request, message}
  def method_not_found(message \\ "Method not found."), do: {:error, @method_not_found, message}
  def invalid_params(message), do: {:error, @invalid_params, message}

  def rate_limited(message \\ "Rate limit exceeded. Please try again later."), do: {:error, @rate_limited, message}
end
