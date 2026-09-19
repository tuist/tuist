defmodule Tuist.DNS do
  @moduledoc """
  Whether a host's DNS record is published, asked of the nameservers
  authoritative for its zone rather than of a caching resolver.

  A caching resolver keeps an answer that a name does not exist for the zone's
  negative TTL, 30 minutes for `tuist.dev`. Asking one about a record that is
  about to be published, as a new Kura instance's activation does from the
  moment the instance is applied, delays noticing the record by that long, and
  leaves the negative answer in the public resolvers clients may share. The
  authoritative nameservers answer from the zone itself, so a record is seen as
  soon as it is published and nothing caches the answers before it.

  The zone's nameservers are found through the pod's resolver, starting from
  the host's parent, so the host itself is never asked about there. When no
  authoritative answer can be had, the host is resolved through the pod's
  resolver instead: a host outside public DNS such as `localhost`, nameservers
  that do not answer, or a network that intercepts DNS, whose answers do not
  carry the authoritative flag.

  Finding those nameservers costs two more lookups — the zone's NS records and
  each nameserver's address — and `:inet_res.lookup/5` does not go through the
  resolver's cache, so a caller polling a host twice a second would pay them on
  every call. The set is cached in memory per node instead: a zone's NS records
  change on the order of years, and the cost of being a few minutes stale is
  asking a nameserver that no longer serves the zone, which reads as
  `:unavailable` and falls back to the pod's resolver.
  """

  alias Tuist.KeyValueStore

  @timeout_ms 1_000
  @nameservers_ttl to_timeout(minute: 10)

  @doc """
  `:ok` once `host` resolves. `{:error, :not_published}` when the zone's
  authoritative nameservers have no record for it; any other error comes from
  the pod's resolver.
  """
  def record_published(host, opts \\ []) when is_binary(host) do
    name = String.to_charlist(host)

    case :inet.parse_address(name) do
      {:ok, _address} ->
        :ok

      {:error, _reason} ->
        case authoritative_answer(name, opts) do
          :found -> :ok
          :not_found -> {:error, :not_published}
          :unavailable -> resolve(name)
        end
    end
  end

  defp authoritative_answer(name, opts) do
    case zone_nameservers(name, opts) do
      [] ->
        :unavailable

      addresses ->
        port = Keyword.get(opts, :authoritative_port, 53)

        name
        |> :inet_res.resolve(:in, :a,
          nameservers: Enum.map(addresses, &{&1, port}),
          recurse: false,
          retry: 1,
          timeout: @timeout_ms,
          nxdomain_reply: true
        )
        |> classify()
    end
  end

  defp classify({:ok, message}) do
    cond do
      not authoritative?(message) -> :unavailable
      :inet_dns.msg(message, :anlist) == [] -> :not_found
      true -> :found
    end
  end

  defp classify({:error, {:nxdomain, message}}) do
    if authoritative?(message), do: :not_found, else: :unavailable
  end

  defp classify({:error, _reason}), do: :unavailable

  defp authoritative?(message) do
    message |> :inet_dns.msg(:header) |> :inet_dns.header(:aa)
  end

  # The closest enclosing zone is the longest parent that has NS records.
  defp zone_nameservers(name, opts) do
    lookup_opts =
      case Keyword.fetch(opts, :resolver_nameservers) do
        {:ok, nameservers} -> [nameservers: nameservers]
        :error -> []
      end

    # Keyed by the parents rather than the host, which is what makes one
    # lookup serve every instance in the zone, and by the resolver, so a caller
    # pointing at its own nameservers never reads a set discovered through the
    # pod's. A failed discovery is not cached: it falls back to the pod's
    # resolver, whose negative answers are exactly what this module exists to
    # avoid holding on to.
    key = [
      __MODULE__,
      :zone_nameservers,
      name |> parent_domains() |> Enum.join(","),
      inspect(lookup_opts)
    ]

    case KeyValueStore.get(key) do
      nil ->
        case resolve_zone_nameservers(name, lookup_opts) do
          [] ->
            []

          addresses ->
            KeyValueStore.put(key, addresses, ttl: @nameservers_ttl)
            addresses
        end

      addresses ->
        addresses
    end
  end

  defp resolve_zone_nameservers(name, lookup_opts) do
    name
    |> parent_domains()
    |> Enum.find_value([], fn domain ->
      case :inet_res.lookup(domain, :in, :ns, lookup_opts, @timeout_ms) do
        [] -> nil
        nameservers -> Enum.flat_map(nameservers, &:inet_res.lookup(&1, :in, :a, lookup_opts, @timeout_ms))
      end
    end)
  end

  # Stops short of the top-level domain, whose nameservers only refer onwards.
  defp parent_domains(name) do
    labels = name |> List.to_string() |> String.trim_trailing(".") |> String.split(".")

    for dropped <- 1..(length(labels) - 2)//1 do
      labels |> Enum.drop(dropped) |> Enum.join(".") |> String.to_charlist()
    end
  end

  defp resolve(name) do
    case :inet.gethostbyname(name) do
      {:ok, _hostent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
