defmodule TuistWeb.Socket do
  use Phoenix.Socket

  alias Tuist.Authentication

  channel("qa_logs:*", TuistWeb.QALogChannel)
  channel("runner:*", TuistWeb.RunnerChannel)

  def connect(%{"token" => token}, socket, _connect_info) do
    case authenticate_socket(token) do
      {:ok, subject} ->
        socket = assign(socket, :current_subject, subject)
        {:ok, socket}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  def id(socket) do
    case socket.assigns do
      %{current_subject: %{account: %{id: account_id}}} -> "account:#{account_id}"
      %{current_subject: :runner} -> "runner"
      _ -> nil
    end
  end

  defp authenticate_socket(token) do
    # Check for runner token first
    if token == runner_token() do
      {:ok, :runner}
    else
      case Authentication.authenticated_subject(token) do
        nil ->
          {:error, :unauthenticated}

        subject ->
          {:ok, subject}
      end
    end
  end

  defp runner_token do
    Application.get_env(:tuist, :runner_token, "tuist-runner-secret")
  end
end
