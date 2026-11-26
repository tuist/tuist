defmodule LuftServer.AISubscriptions do
  @moduledoc """
  The person's AI subscriptions (Claude, ChatGPT), which Tuist stores and
  serves (`/api/me/ai-subscriptions`). Luft forwards the person's requests with
  its server-held Tuist credentials and never sees a subscription credential.

  Every open `ai_subscriptions` channel shows the current state: a change made
  through Luft reaches the person's channels at once through `topic/1`, and
  the channels read Tuist again periodically, so a change made elsewhere, such
  as Tuist's settings page, shows up too.
  """

  alias LuftServer.Config
  alias LuftServer.Sessions
  alias LuftServer.Threads.Provider

  def topic(%{user_sub: user_sub}), do: "ai_subscriptions:" <> user_sub

  @doc "The person's subscriptions: `{:ok, subscriptions}` or the upstream failure."
  def list(session) do
    case request(session, :get, "") do
      {:ok, 200, body} -> subscriptions(body)
      {:ok, status, _body} -> {:error, status}
      error -> error
    end
  end

  @doc """
  Sends one request to Tuist's `/api/me/ai-subscriptions<path>` as the
  session's person: `{:ok, status, body}`, with every subscription list in a
  body annotated with whether Luft threads can run on it.
  """
  def request(session, method, path, opts \\ []) do
    with {:ok, token} <- Sessions.access_token(session) do
      Config.req_options()
      |> Keyword.merge(
        method: method,
        url: Config.tuist_issuer() <> "/api/me/ai-subscriptions" <> path,
        auth: {:bearer, token},
        retry: false,
        redirect: false,
        receive_timeout: 30_000
      )
      |> Keyword.merge(opts)
      |> Req.request()
      |> case do
        {:ok, %{status: status, body: body}} -> {:ok, status, annotate(body)}
        {:error, _reason} -> {:error, :unavailable}
      end
    end
  end

  @doc "Tells the person's open channels what their subscriptions are now."
  def broadcast(session, subscriptions),
    do:
      Phoenix.PubSub.broadcast(
        LuftServer.PubSub,
        topic(session),
        {:ai_subscriptions, subscriptions}
      )

  def subscriptions(%{"subscriptions" => subscriptions}) when is_list(subscriptions),
    do: {:ok, subscriptions}

  def subscriptions(_body), do: {:error, :invalid_response}

  defp annotate(%{"subscriptions" => subscriptions} = body) when is_list(subscriptions) do
    %{
      body
      | "subscriptions" =>
          Enum.map(subscriptions, fn
            %{"provider" => provider} = subscription ->
              Map.put(subscription, "runs_threads", Provider.runs_threads?(provider))

            subscription ->
              subscription
          end)
    }
  end

  defp annotate(body), do: body
end
