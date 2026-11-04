defmodule TuistWeb.API.AISubscriptionsController do
  @moduledoc """
  The signed-in user's personal AI subscriptions (`Tuist.Accounts.AISubscriptions`)
  over the API. Only a user can manage them: a user session or the signed-in
  Tuist app. Account and project tokens, and other OAuth clients, get a 403,
  and users without the ai flag (`Tuist.FeatureFlags.ai_enabled?/1`) a 404.
  Responses are metadata only and never cached; no credential is returned.
  """
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Accounts.AISubscriptions
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.FeatureFlags
  alias Tuist.Push
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.Authentication

  # Reject other credentials before validating their requests.
  plug :require_user

  plug(TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_message: TuistWeb.RenderAPIErrorPlug
  )

  tags ["AI subscriptions"]

  @subscription_schema %Schema{
    title: "AISubscription",
    type: :object,
    properties: %{
      # An open string, so a provider added later does not break older clients.
      provider: %Schema{type: :string, description: "The provider. Known values: `claude`, `chatgpt`."},
      connected: %Schema{type: :boolean, description: "Whether credentials are saved for the provider."},
      updated_at: %Schema{
        type: :string,
        format: :"date-time",
        nullable: true,
        description: "When the connection last changed, or null if it was never connected."
      },
      login_available: %Schema{
        type: :boolean,
        description: "Whether the server can connect the provider. ChatGPT needs an OAuth client the operator configures."
      }
    },
    required: [:provider, :connected, :updated_at, :login_available]
  }

  @subscriptions_schema %Schema{
    title: "AISubscriptions",
    type: :object,
    properties: %{subscriptions: %Schema{type: :array, items: @subscription_schema}},
    required: [:subscriptions]
  }

  @providers %{"claude" => :claude, "chatgpt" => :chatgpt}

  @login_id_description "The opaque sign-in ID that `startChatGPTSubscriptionLogin` returned."

  @base_responses %{
    unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
    forbidden: {"Only a signed-in user can manage AI subscriptions", "application/json", Error},
    not_found: {"AI subscriptions are not available to this user", "application/json", Error}
  }

  operation(:index,
    summary: "Lists the signed-in user's AI subscriptions",
    description: "Returns connection metadata for every supported provider. Credentials are never returned.",
    operation_id: "listAISubscriptions",
    responses: Map.put(@base_responses, :ok, {"The user's AI subscriptions", "application/json", @subscriptions_schema})
  )

  def index(conn, _params), do: json(conn, subscriptions_json(conn.assigns.ai_subscriptions_user))

  operation(:connect_claude,
    summary: "Connects the signed-in user's Claude subscription",
    description:
      "Saves the subscription token `claude setup-token` prints, replacing any saved one. Tuist validates its format only, not that the subscription can serve requests. The token is never returned.",
    operation_id: "connectClaudeSubscription",
    request_body:
      {"Claude subscription token", "application/json",
       %Schema{
         type: :object,
         properties: %{
           token: %Schema{
             type: :string,
             description: "The token `claude setup-token` prints. Not an Anthropic API key."
           }
         },
         required: [:token]
       }, required: true},
    responses:
      Map.merge(@base_responses, %{
        ok: {"The user's AI subscriptions", "application/json", @subscriptions_schema},
        unprocessable_entity: {"The token is not a Claude subscription token", "application/json", Error},
        service_unavailable: {"The token could not be saved", "application/json", Error}
      })
  )

  def connect_claude(%{body_params: %{token: token}} = conn, _params) do
    user = conn.assigns.ai_subscriptions_user

    case AISubscriptions.connect_claude(user, token) do
      :ok -> json(conn, subscriptions_json(user))
      {:error, reason} -> error(conn, reason)
    end
  end

  operation(:start_chatgpt_login,
    summary: "Starts connecting the signed-in user's ChatGPT subscription",
    description:
      "Starts an OpenAI device sign-in. Show the user the verification URL and code, then poll with the login ID no faster than `interval` seconds until it connects or `expires_at` passes. Saved credentials stay until the sign-in succeeds.",
    operation_id: "startChatGPTSubscriptionLogin",
    responses:
      Map.merge(@base_responses, %{
        ok:
          {"The pending sign-in", "application/json",
           %Schema{
             title: "ChatGPTSubscriptionLogin",
             type: :object,
             properties: %{
               login_id: %Schema{type: :string, description: "The opaque ID to poll and cancel the sign-in with."},
               user_code: %Schema{type: :string, description: "The code the user enters on the verification page."},
               verification_url: %Schema{type: :string, description: "The OpenAI page where the user enters the code."},
               interval: %Schema{type: :integer, description: "The minimum number of seconds between polls."},
               expires_at: %Schema{type: :string, format: :"date-time", description: "When the sign-in expires."}
             },
             required: [:login_id, :user_code, :verification_url, :interval, :expires_at]
           }},
        too_many_requests: {"Too many sign-in attempts. Try again in a few minutes.", "application/json", Error},
        bad_gateway: {"OpenAI could not start the sign-in", "application/json", Error},
        service_unavailable: {"ChatGPT sign-in is not configured on this server", "application/json", Error}
      })
  )

  def start_chatgpt_login(conn, _params) do
    case AISubscriptions.start_chatgpt(conn.assigns.ai_subscriptions_user) do
      {:ok, login} -> json(conn, %{login | expires_at: DateTime.to_iso8601(login.expires_at)})
      {:error, reason} -> error(conn, reason)
    end
  end

  operation(:poll_chatgpt_login,
    summary: "Polls a pending ChatGPT sign-in",
    description:
      "Returns `pending` until the user approves the code, then `connected`. Polls sooner than the sign-in's interval return `pending` without asking OpenAI.",
    operation_id: "pollChatGPTSubscriptionLogin",
    request_body:
      {"Sign-in", "application/json",
       %Schema{
         type: :object,
         properties: %{login_id: %Schema{type: :string, description: @login_id_description}},
         required: [:login_id]
       }, required: true},
    responses:
      Map.merge(@base_responses, %{
        ok:
          {"The sign-in status", "application/json",
           %Schema{
             title: "ChatGPTSubscriptionLoginStatus",
             type: :object,
             properties: %{
               status: %Schema{type: :string, description: "Known values: `pending`, `connected`."}
             },
             required: [:status]
           }},
        not_found: {"No pending sign-in has that ID, or AI subscriptions are not available", "application/json", Error},
        gone: {"The sign-in expired. Start a new one.", "application/json", Error},
        bad_gateway: {"OpenAI rejected the sign-in. Start a new one.", "application/json", Error}
      })
  )

  def poll_chatgpt_login(%{body_params: %{login_id: login_id}} = conn, _params) do
    case AISubscriptions.poll_chatgpt(conn.assigns.ai_subscriptions_user, login_id) do
      {:ok, status} -> json(conn, %{status: status})
      {:error, reason} -> error(conn, reason)
    end
  end

  operation(:cancel_chatgpt_login,
    summary: "Cancels a pending ChatGPT sign-in",
    description: "Discards the pending sign-in. A ChatGPT subscription that is already connected stays connected.",
    operation_id: "cancelChatGPTSubscriptionLogin",
    parameters: [
      login_id: [in: :query, type: :string, required: true, description: @login_id_description]
    ],
    responses:
      Map.merge(@base_responses, %{
        no_content: "The sign-in was cancelled",
        not_found: {"No pending sign-in has that ID, or AI subscriptions are not available", "application/json", Error}
      })
  )

  def cancel_chatgpt_login(conn, %{login_id: login_id}) do
    case AISubscriptions.cancel_chatgpt(conn.assigns.ai_subscriptions_user, login_id) do
      :ok -> send_resp(conn, :no_content, "")
      {:error, reason} -> error(conn, reason)
    end
  end

  operation(:delete,
    summary: "Disconnects one of the signed-in user's AI subscriptions",
    description:
      "Deletes the provider's saved credentials and any pending sign-in. It does not revoke the authorization at the provider.",
    operation_id: "disconnectAISubscription",
    parameters: [
      provider: [
        in: :path,
        schema: %Schema{type: :string, enum: Map.keys(@providers)},
        required: true,
        description: "The provider to disconnect."
      ]
    ],
    responses: Map.put(@base_responses, :ok, {"The user's AI subscriptions", "application/json", @subscriptions_schema})
  )

  def delete(%{path_params: %{"provider" => provider}} = conn, _params) do
    user = conn.assigns.ai_subscriptions_user
    :ok = AISubscriptions.disconnect(user, Map.fetch!(@providers, provider))
    json(conn, subscriptions_json(user))
  end

  # A user session, or the signed-in Tuist app, whose OAuth access tokens
  # authenticate as the user's account with the user as issuer. Other OAuth
  # clients have the same token shape, so the app's grant is checked.
  defp require_user(conn, _opts) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    case user(conn) do
      %User{} = user ->
        if FeatureFlags.ai_enabled?(user),
          do: assign(conn, :ai_subscriptions_user, user),
          else: conn |> error(:not_found) |> halt()

      nil ->
        conn
        |> put_status(:forbidden)
        |> json(%{message: "Only a signed-in user can manage AI subscriptions."})
        |> halt()
    end
  end

  defp user(conn) do
    case Authentication.authenticated_subject(conn) do
      %User{} = user ->
        user

      %AuthenticatedAccount{issued_by: %User{} = user} ->
        with ["Bearer " <> bearer] <- get_req_header(conn, "authorization"),
             {:ok, _session} <- Push.oauth_session(bearer, user) do
          user
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp subscriptions_json(user) do
    %{
      subscriptions:
        user
        |> AISubscriptions.list()
        |> Enum.map(fn subscription ->
          %{subscription | updated_at: subscription.updated_at && DateTime.to_iso8601(subscription.updated_at)}
        end)
    }
  end

  defp error(conn, reason) do
    {status, message} = error_response(reason)
    conn |> put_status(status) |> json(%{message: message})
  end

  defp error_response(:not_found), do: {:not_found, "Not found."}

  defp error_response(:invalid_claude_token),
    do: {:unprocessable_entity, "Provide the subscription token that claude setup-token prints."}

  defp error_response(:rate_limited),
    do: {:too_many_requests, "Too many ChatGPT sign-in attempts. Try again in a few minutes."}

  defp error_response(:login_expired), do: {:gone, "The ChatGPT sign-in expired. Start a new one."}

  defp error_response(:chatgpt_not_configured),
    do: {:service_unavailable, "ChatGPT sign-in is not configured on this server."}

  defp error_response(:storage_unavailable), do: {:service_unavailable, "The subscription could not be saved. Try again."}

  defp error_response(:chatgpt_login_failed), do: {:bad_gateway, "OpenAI rejected the ChatGPT sign-in. Start a new one."}

  defp error_response(_reason), do: {:bad_gateway, "OpenAI could not be reached. Try again later."}
end
