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
  """

  @timeout_ms 1_000

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
