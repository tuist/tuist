defmodule TuistWeb.Socket do
  use Phoenix.Socket

  alias Tuist.Authentication

  channel("qa_logs:*", TuistWeb.QALogChannel)

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
      _ -> nil
    end
  end

  defp authenticate_socket(token) do
    case Authentication.authenticated_subject(token) do
      nil ->
        {:error, :unauthenticated}

      subject ->
        {:ok, subject}
    end
  end
end
