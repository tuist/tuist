defmodule Pulse.Sentry do
  @moduledoc "Operator-provisioned, ingest-only Sentry project credentials. No accounts database."

  alias Pulse.Auth.Issuer
  alias Pulse.Runtime

  def validate_projects!(projects) do
    valid? =
      is_map(projects) and map_size(projects) <= 256 and
        Enum.all?(projects, &valid_project?/1)

    if valid?, do: projects, else: raise(ArgumentError, "PULSE_SENTRY_PROJECTS_JSON contains invalid projects")
  end

  @doc "Whether `{id, project}` is a valid Sentry project entry (environment or issuer status list)."
  def valid_project?({id, value}) when is_binary(id) and is_map(value) do
    Regex.match?(~r/\A[0-9]{1,32}\z/, id) and
      Map.keys(value) -- ~w(tenant service public_key_hashes allowed_domains) == [] and
      valid_name?(value["tenant"]) and valid_name?(value["service"]) and
      valid_domains?(Map.get(value, "allowed_domains", ["*"])) and
      valid_key_hashes?(value["public_key_hashes"])
  end

  def valid_project?(_), do: false

  defp valid_key_hashes?(hashes) when is_list(hashes) and length(hashes) in 1..8 do
    Enum.all?(hashes, &(is_binary(&1) and Regex.match?(~r/\A[0-9a-f]{64}\z/, &1)))
  end

  defp valid_key_hashes?(_), do: false

  @doc """
  Whether the request carries Sentry credentials outside the body (header or
  `sentry_key` query parameter), so it can be authorized before the body is read.
  """
  def request_credentials?(conn) do
    conn = Plug.Conn.fetch_query_params(conn)

    Plug.Conn.get_req_header(conn, "x-sentry-auth") not in [[], [""]] or
      Enum.any?(Plug.Conn.get_req_header(conn, "authorization"), &Regex.match?(~r/\Asentry /i, &1)) or
      is_binary(conn.query_params["sentry_key"])
  end

  # Operator-configured projects take precedence over projects published in
  # the issuer status list for the same ID.
  defp projects do
    Map.merge(
      Issuer.sentry_projects(),
      Keyword.get(Runtime.get_env(:pulse, __MODULE__, []), :projects, %{})
    )
  end

  def authorize(conn, project_id, headers) do
    conn = Plug.Conn.fetch_query_params(conn)
    projects = projects()
    projects = if is_nil(project_id), do: projects, else: Map.take(projects, [project_id])

    with true <- map_size(projects) > 0,
         {:ok, keys} <- credentials(conn, project_id, headers),
         [key | rest] <- keys,
         true <- Enum.all?(rest, &(&1 == key)),
         digest = Base.encode16(:crypto.hash(:sha256, key), case: :lower),
         [{id, project}] <-
           Enum.filter(projects, fn {_id, project} ->
             Enum.any?(project["public_key_hashes"], &Plug.Crypto.secure_compare(&1, digest))
           end),
         true <- allowed_origin?(Plug.Conn.get_req_header(conn, "origin"), project) do
      {:ok, id, project}
    else
      _ -> {:error, :invalid_sentry_key}
    end
  end

  defp credentials(conn, project, headers) do
    authorization =
      case Plug.Conn.get_req_header(conn, "authorization") do
        [header] = values -> if Regex.match?(~r/\Asentry /i, header), do: values, else: []
        values -> values
      end

    with {:ok, auth} <- auth_header(Plug.Conn.get_req_header(conn, "x-sentry-auth")),
         {:ok, authorization} <- auth_header(authorization),
         {:ok, dsn} <- dsn_key(headers["dsn"], project) do
      keys = Enum.reject([auth, authorization, conn.query_params["sentry_key"], dsn], &is_nil/1)

      if Enum.all?(keys, &(is_binary(&1) and byte_size(&1) in 1..256)),
        do: {:ok, keys},
        else: {:error, :invalid_sentry_key}
    end
  end

  defp auth_header([]), do: {:ok, nil}
  defp auth_header([""]), do: {:ok, nil}

  defp auth_header([<<scheme::binary-size(7), fields::binary>>]) do
    fields = Enum.map(String.split(fields, ","), &String.split(String.trim(&1), "=", parts: 2))

    case {String.downcase(scheme, :ascii), Enum.filter(fields, &match?(["sentry_key", _], &1))} do
      {"sentry ", [["sentry_key", key]]} -> {:ok, key}
      _ -> {:error, :invalid_sentry_key}
    end
  end

  defp auth_header(_), do: {:error, :invalid_sentry_key}

  defp dsn_key(nil, _), do: {:ok, nil}

  defp dsn_key(dsn, project) when is_binary(dsn) do
    uri = URI.parse(dsn)

    if uri.scheme in ["http", "https"] and is_binary(uri.host) and is_binary(uri.userinfo) and
         List.last(String.split(uri.path || "", "/")) == project do
      {:ok, uri.userinfo |> String.split(":", parts: 2) |> hd()}
    else
      {:error, :invalid_sentry_key}
    end
  end

  defp dsn_key(_, _), do: {:error, :invalid_sentry_key}

  defp valid_domains?(domains) when is_list(domains) and length(domains) <= 32 do
    Enum.all?(domains, &(is_binary(&1) and byte_size(&1) in 1..256 and String.valid?(&1)))
  end

  defp valid_domains?(_), do: false

  # No Origin is normal for server SDKs. Resolve credentials first so origin
  # restrictions can never disambiguate projects sharing an ingest key.
  defp allowed_origin?([], _project), do: true

  defp allowed_origin?(_origins, project) when not is_map_key(project, "allowed_domains"), do: true

  defp allowed_origin?([origin], project) when byte_size(origin) <= 2048 do
    case URI.new(origin) do
      {:ok, %URI{scheme: scheme, host: host, userinfo: nil, query: nil, fragment: nil, path: path}}
      when scheme in ["http", "https"] and host not in [nil, ""] and path in [nil, ""] ->
        {scheme, domain, port} = origin_parts(origin)

        Enum.any?(project["allowed_domains"], fn pattern ->
          {expected_scheme, expected_domain, expected_port} = origin_parts(pattern)

          (is_nil(expected_scheme) or scheme == expected_scheme) and
            (is_nil(expected_port) or port == expected_port) and domain_matches?(domain, expected_domain)
        end)

      _ ->
        false
    end
  end

  defp allowed_origin?(_, _), do: false

  # Relay compares explicit scheme/domain/port components. Omitted or whole-*
  # components are wildcards; a pattern's path does not participate.
  defp origin_parts(value) do
    {scheme, rest} =
      case String.split(value, "://", parts: 2) do
        [scheme, rest] -> {origin_component(scheme), rest}
        [rest] -> {nil, rest}
      end

    authority = rest |> String.split("/", parts: 2) |> hd()

    {domain, port} =
      case String.split(authority, ~r/:(?!.*[:\]])/, parts: 2) do
        [domain, port] -> {domain, origin_component(port)}
        [domain] -> {domain, nil}
      end

    {scheme, origin_component(domain), port}
  end

  defp origin_component("*"), do: nil
  defp origin_component(value), do: String.downcase(value)

  defp domain_matches?(_domain, nil), do: true
  defp domain_matches?(domain, domain), do: true

  defp domain_matches?(domain, "*" <> suffix) when is_binary(domain) do
    suffix = String.replace_prefix(suffix, ".", "")
    suffix != "" and (domain == suffix or String.ends_with?(domain, "." <> suffix))
  end

  defp domain_matches?(_, _), do: false

  defp valid_name?(name), do: is_binary(name) and Regex.match?(~r/\A[A-Za-z0-9_.-]{1,128}\z/, name)
end
