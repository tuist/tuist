defmodule TuistWeb.Turnstile do
  @moduledoc false

  alias Tuist.Environment

  require Logger

  @endpoint "https://challenges.cloudflare.com/turnstile/v0/siteverify"

  def required? do
    Environment.turnstile_required?()
  end

  def site_key do
    Environment.turnstile_site_key()
  end

  def verify(token, opts \\ []) do
    required? = Keyword.get(opts, :required?, required?())

    if required? do
      verify_required(token, opts)
    else
      :ok
    end
  end

  defp verify_required(token, opts) do
    secret_key = Keyword.get(opts, :secret_key, Environment.turnstile_secret_key())

    cond do
      not is_binary(secret_key) or secret_key == "" ->
        Logger.error("Turnstile is enabled without a secret key")
        {:error, :misconfigured}

      not is_binary(token) or token == "" ->
        {:error, :missing_token}

      true ->
        verify_token(token, secret_key, opts)
    end
  end

  defp verify_token(token, secret_key, opts) do
    request = Keyword.get(opts, :request, &Req.post/2)
    endpoint = Keyword.get(opts, :endpoint, @endpoint)
    expected_action = Keyword.get(opts, :expected_action)
    expected_hostname = Keyword.get_lazy(opts, :expected_hostname, &expected_hostname/0)

    case request.(endpoint,
           form: %{secret: secret_key, response: token},
           connect_options: [timeout: 1_000],
           receive_timeout: 5_000
         ) do
      {:ok, %Req.Response{status: 200, body: %{"success" => true} = body}} ->
        with :ok <- validate_action(body, expected_action) do
          validate_hostname(body, expected_hostname)
        end

      {:ok, %Req.Response{status: 200}} ->
        {:error, :rejected}

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("Turnstile verification returned an unexpected status", status: status)
        {:error, :unavailable}

      {:error, _reason} ->
        Logger.warning("Turnstile verification request failed")
        {:error, :unavailable}
    end
  end

  defp validate_action(_body, nil), do: :ok

  defp validate_action(%{"action" => action}, expected_action) when action == expected_action, do: :ok

  defp validate_action(_body, _expected_action), do: {:error, :rejected}

  defp expected_hostname do
    Environment.app_url()
    |> URI.parse()
    |> Map.get(:host)
  end

  defp validate_hostname(%{"hostname" => hostname}, expected_hostname)
       when is_binary(expected_hostname) and expected_hostname != "" and hostname == expected_hostname, do: :ok

  defp validate_hostname(_body, expected_hostname) when not is_binary(expected_hostname) or expected_hostname == "" do
    Logger.error("Turnstile is enabled without a valid hosted URL")
    {:error, :misconfigured}
  end

  defp validate_hostname(_body, _expected_hostname), do: {:error, :rejected}
end
