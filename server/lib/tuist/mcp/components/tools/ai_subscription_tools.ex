defmodule Tuist.MCP.Components.Tools.AISubscriptionTools do
  @moduledoc """
  Shared helpers for the tools that manage the authenticated user's personal AI
  subscriptions (`Tuist.Accounts.AISubscriptions`). They act only for a user,
  only while `Tuist.FeatureFlags.ai_enabled?/1` holds for them, and never
  return credentials. Under a WebMCP account scope, only the user's personal
  account is in scope.
  """

  alias Tuist.Accounts.AISubscriptions
  alias Tuist.Accounts.User
  alias Tuist.FeatureFlags
  alias Tuist.MCP.Formatter

  def subscriptions_schema do
    %{
      "type" => "object",
      "properties" => %{
        "subscriptions" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "provider" => %{"type" => "string", "description" => "Known values: claude, chatgpt."},
              "connected" => %{"type" => "boolean"},
              "updated_at" => %{"type" => ["string", "null"]},
              "login_available" => %{"type" => "boolean"}
            },
            "required" => ["provider", "connected", "updated_at", "login_available"],
            "additionalProperties" => false
          }
        }
      },
      "required" => ["subscriptions"],
      "additionalProperties" => false
    }
  end

  def user(%{assigns: assigns}) do
    with %User{} = user <- assigns[:current_user],
         true <- in_scope?(assigns[:mcp_account_scope], user),
         true <- FeatureFlags.ai_enabled?(user) do
      {:ok, user}
    else
      _ -> {:error, "AI subscriptions are only available to an authenticated user with the AI feature flag."}
    end
  end

  defp in_scope?(nil, _user), do: true
  defp in_scope?(%{user_id: user_id}, %User{id: user_id}), do: true
  defp in_scope?(_scope, _user), do: false

  def subscriptions(user) do
    %{
      subscriptions:
        user
        |> AISubscriptions.list()
        |> Enum.map(fn subscription ->
          %{
            provider: Atom.to_string(subscription.provider),
            connected: subscription.connected,
            updated_at: Formatter.iso8601(subscription.updated_at),
            login_available: subscription.login_available
          }
        end)
    }
  end
end

defmodule Tuist.MCP.Components.Tools.ListAISubscriptions do
  @moduledoc """
  List the authenticated user's personal AI subscriptions.
  """

  use Tuist.MCP.Tool,
    name: "list_ai_subscriptions",
    title: "List AI Subscriptions",
    read_only_hint: true,
    schema: %{"type" => "object", "properties" => %{}, "additionalProperties" => false},
    output_schema: Tuist.MCP.Components.Tools.AISubscriptionTools.subscriptions_schema()

  alias Tuist.MCP.Components.Tools.AISubscriptionTools

  @impl EMCP.Tool
  def description do
    "List whether the authenticated user's personal Claude and ChatGPT subscriptions are connected for threads. " <>
      "Returns metadata only, never credentials."
  end

  def execute(conn, _args) do
    with {:ok, user} <- AISubscriptionTools.user(conn) do
      {:ok, AISubscriptionTools.subscriptions(user)}
    end
  end
end

defmodule Tuist.MCP.Components.Tools.ConnectClaudeSubscription do
  @moduledoc """
  Save the authenticated user's Claude subscription token.
  """

  use Tuist.MCP.Tool,
    name: "connect_claude_subscription",
    title: "Connect Claude Subscription",
    read_only_hint: false,
    schema: %{
      "type" => "object",
      "properties" => %{
        "token" => %{
          "type" => "string",
          "description" =>
            "Secret. The subscription token `claude setup-token` prints, not an Anthropic API key. Only pass a token the user explicitly provided for this purpose."
        }
      },
      "required" => ["token"],
      "additionalProperties" => false
    },
    output_schema: Tuist.MCP.Components.Tools.AISubscriptionTools.subscriptions_schema()

  alias Tuist.Accounts.AISubscriptions
  alias Tuist.MCP.Components.Tools.AISubscriptionTools

  @impl EMCP.Tool
  def description do
    "Create or replace the authenticated user's personal Claude subscription token for threads. " <>
      "The token is a secret: only call this with a token the user explicitly gave you for this purpose, because it passes through the MCP client and model. " <>
      "Prefer asking the user to paste it in the dashboard's AI subscriptions settings instead. " <>
      "Validates the token's format, not that the subscription works; never returns credentials."
  end

  def execute(conn, %{"token" => token}) do
    with {:ok, user} <- AISubscriptionTools.user(conn) do
      case AISubscriptions.connect_claude(user, token) do
        :ok -> {:ok, AISubscriptionTools.subscriptions(user)}
        {:error, :invalid_claude_token} -> {:error, "Provide the subscription token that claude setup-token prints."}
        {:error, _reason} -> {:error, "Could not save the Claude subscription. Try again."}
      end
    end
  end
end

defmodule Tuist.MCP.Components.Tools.StartChatGPTSubscriptionLogin do
  @moduledoc """
  Start connecting the authenticated user's ChatGPT subscription.
  """

  use Tuist.MCP.Tool,
    name: "start_chatgpt_subscription_login",
    title: "Start ChatGPT Subscription Login",
    read_only_hint: false,
    open_world_hint: true,
    schema: %{"type" => "object", "properties" => %{}, "additionalProperties" => false},
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "login_id" => %{"type" => "string"},
        "user_code" => %{"type" => "string"},
        "verification_url" => %{"type" => "string"},
        "interval" => %{"type" => "integer"},
        "expires_at" => %{"type" => "string"}
      },
      "required" => ["login_id", "user_code", "verification_url", "interval", "expires_at"],
      "additionalProperties" => false
    }

  alias Tuist.Accounts.AISubscriptions
  alias Tuist.MCP.Components.Tools.AISubscriptionTools
  alias Tuist.MCP.Formatter

  @impl EMCP.Tool
  def description do
    "Start connecting the authenticated user's personal ChatGPT subscription for threads through OpenAI device sign-in. " <>
      "Show the user the verification URL and code; only the user can approve it on OpenAI's website. " <>
      "Then call poll_chatgpt_subscription_login no faster than every interval seconds until it connects or expires (15 minutes). " <>
      "Starting again replaces a pending sign-in. Saved credentials stay until the sign-in succeeds. " <>
      "Never asks for a password or returns provider tokens."
  end

  def execute(conn, _args) do
    with {:ok, user} <- AISubscriptionTools.user(conn) do
      case AISubscriptions.start_chatgpt(user) do
        {:ok, login} ->
          {:ok, %{login | expires_at: Formatter.iso8601(login.expires_at)}}

        {:error, :rate_limited} ->
          {:error, "Too many ChatGPT sign-in attempts. Wait five minutes before trying again."}

        {:error, :chatgpt_not_configured} ->
          {:error, "ChatGPT sign-in is not configured on this server."}

        {:error, _reason} ->
          {:error, "Could not start the ChatGPT sign-in. Try again later."}
      end
    end
  end
end

defmodule Tuist.MCP.Components.Tools.PollChatGPTSubscriptionLogin do
  @moduledoc """
  Poll a pending ChatGPT subscription sign-in.
  """

  use Tuist.MCP.Tool,
    name: "poll_chatgpt_subscription_login",
    title: "Poll ChatGPT Subscription Login",
    read_only_hint: false,
    open_world_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "login_id" => %{
          "type" => "string",
          "description" => "The login_id that start_chatgpt_subscription_login returned."
        }
      },
      "required" => ["login_id"],
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"status" => %{"type" => "string", "enum" => ["pending", "connected"]}},
      "required" => ["status"],
      "additionalProperties" => false
    }

  alias Tuist.Accounts.AISubscriptions
  alias Tuist.MCP.Components.Tools.AISubscriptionTools

  @impl EMCP.Tool
  def description do
    "Check a pending ChatGPT sign-in. Returns pending until the user approves the code, then connected and saves the subscription. " <>
      "Polling faster than the sign-in's interval returns pending without contacting OpenAI."
  end

  def execute(conn, %{"login_id" => login_id}) do
    with {:ok, user} <- AISubscriptionTools.user(conn) do
      case AISubscriptions.poll_chatgpt(user, login_id) do
        {:ok, status} -> {:ok, %{status: Atom.to_string(status)}}
        {:error, :not_found} -> {:error, "No pending ChatGPT sign-in has that login_id."}
        {:error, :login_expired} -> {:error, "The ChatGPT sign-in expired. Start a new one."}
        {:error, _reason} -> {:error, "OpenAI rejected the ChatGPT sign-in. Start a new one."}
      end
    end
  end
end

defmodule Tuist.MCP.Components.Tools.CancelChatGPTSubscriptionLogin do
  @moduledoc """
  Cancel a pending ChatGPT subscription sign-in.
  """

  use Tuist.MCP.Tool,
    name: "cancel_chatgpt_subscription_login",
    title: "Cancel ChatGPT Subscription Login",
    read_only_hint: false,
    schema: %{
      "type" => "object",
      "properties" => %{
        "login_id" => %{
          "type" => "string",
          "description" => "The login_id that start_chatgpt_subscription_login returned."
        }
      },
      "required" => ["login_id"],
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"cancelled" => %{"type" => "boolean"}},
      "required" => ["cancelled"],
      "additionalProperties" => false
    }

  alias Tuist.Accounts.AISubscriptions
  alias Tuist.MCP.Components.Tools.AISubscriptionTools

  @impl EMCP.Tool
  def description do
    "Cancel a pending ChatGPT sign-in. A ChatGPT subscription that is already connected stays connected."
  end

  def execute(conn, %{"login_id" => login_id}) do
    with {:ok, user} <- AISubscriptionTools.user(conn) do
      case AISubscriptions.cancel_chatgpt(user, login_id) do
        :ok -> {:ok, %{cancelled: true}}
        {:error, _reason} -> {:error, "No pending ChatGPT sign-in has that login_id."}
      end
    end
  end
end

defmodule Tuist.MCP.Components.Tools.DisconnectAISubscription do
  @moduledoc """
  Disconnect one of the authenticated user's personal AI subscriptions.
  """

  use Tuist.MCP.Tool,
    name: "disconnect_ai_subscription",
    title: "Disconnect AI Subscription",
    read_only_hint: false,
    destructive_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "provider" => %{
          "type" => "string",
          "enum" => ["claude", "chatgpt"],
          "description" => "The provider to disconnect."
        }
      },
      "required" => ["provider"],
      "additionalProperties" => false
    },
    output_schema: Tuist.MCP.Components.Tools.AISubscriptionTools.subscriptions_schema()

  alias Tuist.Accounts.AISubscriptions
  alias Tuist.MCP.Components.Tools.AISubscriptionTools

  @providers %{"claude" => :claude, "chatgpt" => :chatgpt}

  @impl EMCP.Tool
  def description do
    "Delete the authenticated user's saved credentials and any pending sign-in for a personal AI subscription. " <>
      "Does not revoke the authorization at the provider; the user does that on the provider's website."
  end

  def execute(conn, %{"provider" => provider}) do
    with {:ok, user} <- AISubscriptionTools.user(conn) do
      :ok = AISubscriptions.disconnect(user, Map.fetch!(@providers, provider))
      {:ok, AISubscriptionTools.subscriptions(user)}
    end
  end
end
