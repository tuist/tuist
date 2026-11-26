defmodule Tuist.Marketing.Attribution do
  @moduledoc """
  Where visitors and new users come from, for Atlas' acquisition funnel.

  Attribution is read only from what a request already carries: the campaign
  parameters of the URL (`utm_*`, or `ref` as a source shorthand) and the
  `Referer` header. Nothing is stored on the visitor's device, not even in the
  session cookie: links carry the campaign from page to page up to the sign-up
  form, and across an identity provider's round trip it waits on the server,
  keyed by the OAuth `state` the round trip already carries. Two records come
  out of it:

    * `Tuist.Marketing.Attribution.Landing`: one anonymous ClickHouse row per
      visit that arrived from a campaign link on another site or app. It holds the
      campaign and landing path only, no visitor identifier.
    * `Tuist.Marketing.Attribution.SignupAttribution`: the first-touch
      campaign or referring site of a user who signed up in the browser,
      stored with the user and deleted with them.

  Atlas joins both with subscriptions to measure landings, signups and
  paying customers per source and campaign.
  """

  alias Tuist.KeyValueStore
  alias Tuist.Marketing.Attribution.Landing
  alias Tuist.Marketing.Attribution.SignupAttribution

  @campaign_params %{
    "utm_source" => :source,
    "utm_medium" => :medium,
    "utm_campaign" => :campaign,
    "utm_content" => :content,
    "utm_term" => :term
  }

  @max_length 200

  # Long enough to choose a username after the identity provider returns.
  @held_ttl to_timeout(hour: 1)

  def campaign_param_names, do: Map.keys(@campaign_params) ++ ["ref"]

  @doc """
  The campaign a URL's query parameters name, or nil when they name no
  source. `ref` stands in for `utm_source` when that is missing, as on links
  that only carry `?ref=newsletter`.
  """
  def from_params(params) when is_map(params) do
    attribution =
      Map.new(@campaign_params, fn {param, key} -> {key, clean(params[param])} end)

    source = attribution.source || clean(params["ref"])

    if source do
      attribution
      |> Map.put(:source, String.downcase(source))
      |> Map.update!(:medium, &(&1 && String.downcase(&1)))
    end
  end

  def from_params(_params), do: nil

  @doc """
  The host of a `Referer` from another site, without `www.`, or nil when the
  header is missing, unparseable or points at `own_host`.
  """
  def external_referrer_host(referer, own_host) when is_binary(referer) do
    with %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) and host != "" <-
           URI.parse(referer),
         host = host |> String.downcase() |> String.replace_prefix("www.", ""),
         false <- host == normalize_host(own_host) do
      truncate(host)
    else
      _ -> nil
    end
  end

  def external_referrer_host(_referer, _own_host), do: nil

  @doc """
  The campaign parameters of `params`, to carry the campaign along a link.
  """
  def campaign_query(params) when is_map(params) do
    for name <- campaign_param_names(), value = clean(params[name]), into: %{}, do: {name, value}
  end

  def campaign_query(_params), do: %{}

  @doc "`path` with the campaign parameters of `params` added to its query."
  def with_campaign(path, params) do
    case campaign_query(params) do
      query when query == %{} -> path
      query -> path <> if(String.contains?(path, "?"), do: "&", else: "?") <> URI.encode_query(query)
    end
  end

  @doc """
  Keeps a sign-up's campaign on the server for an hour under `key`, while the
  visitor is away at an identity provider. Shared across server instances.
  """
  def hold(key, attribution) when is_list(key) and is_map(attribution) do
    KeyValueStore.put(["signup_attribution" | key], attribution, ttl: @held_ttl, persist_across_deployments: true)
    :ok
  end

  def hold(_key, _attribution), do: :ok

  @doc "The campaign `hold/2` kept under `key`, or nil."
  def held(key) when is_list(key) do
    if Enum.all?(key, &(is_binary(&1) and &1 != "")) do
      KeyValueStore.get(["signup_attribution" | key], persist_across_deployments: true)
    end
  end

  @doc """
  Counts a landing from a campaign link. Buffered into ClickHouse, so the
  request does not wait on the write.
  """
  def record_landing(%{source: source} = attribution, path, referrer_host) when is_binary(source) do
    Landing.Buffer.insert(%{
      id: UUIDv7.generate(),
      source: source,
      medium: attribution[:medium] || "",
      campaign: attribution[:campaign] || "",
      content: attribution[:content] || "",
      term: attribution[:term] || "",
      referrer_host: referrer_host || "",
      path: truncate(path),
      inserted_at: NaiveDateTime.utc_now()
    })

    :ok
  end

  @doc """
  The changeset that stores a new user's first touch, the map `from_params/1`
  returned.
  """
  def signup_changeset(user_id, attrs) do
    SignupAttribution.changeset(%SignupAttribution{user_id: user_id}, attrs)
  end

  defp clean(value) when is_binary(value) do
    value =
      value
      |> String.replace(~r/[[:cntrl:]]/u, "")
      |> String.trim()
      |> truncate()

    if value == "", do: nil, else: value
  end

  defp clean(_value), do: nil

  # Postgres limits `varchar(255)` by code points, and one grapheme can hold
  # many (combining marks, emoji sequences), so cut by code points.
  defp truncate(value), do: value |> String.codepoints() |> Enum.take(@max_length) |> Enum.join()

  defp normalize_host(host) when is_binary(host), do: host |> String.downcase() |> String.replace_prefix("www.", "")
  defp normalize_host(_host), do: nil
end
