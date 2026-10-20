defmodule Tuist.DNSTest do
  use ExUnit.Case, async: true

  alias Tuist.DNS

  @host "app.tuist.test"

  # A nameserver on a loopback port that answers both the lookups a resolver
  # makes (recursion desired) and the queries sent to the zone's authoritative
  # nameservers (no recursion), and reports every question to the test.
  defp start_nameserver(host_answer) do
    {:ok, socket} = :gen_udp.open(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(socket)
    test = self()
    pid = spawn_link(fn -> serve(socket, test, host_answer) end)
    :ok = :gen_udp.controlling_process(socket, pid)
    [resolver_nameservers: [{{127, 0, 0, 1}, port}], authoritative_port: port]
  end

  defp serve(socket, test, host_answer) do
    {:ok, {address, port, packet}} = :gen_udp.recv(socket, 0)
    {:ok, query} = :inet_dns.decode(packet)
    header = :inet_dns.msg(query, :header)
    [question] = :inet_dns.msg(query, :qdlist)
    name = question |> :inet_dns.dns_query(:domain) |> List.to_string()
    type = :inet_dns.dns_query(question, :type)
    send(test, {:asked, name, type, :inet_dns.header(header, :rd)})

    {rcode, authoritative?, answers} = answer(name, type, host_answer)

    reply =
      :inet_dns.make_msg(
        header:
          :inet_dns.make_header(
            id: :inet_dns.header(header, :id),
            qr: true,
            opcode: :query,
            aa: authoritative?,
            rd: :inet_dns.header(header, :rd),
            rcode: rcode
          ),
        qdlist: [question],
        anlist: answers
      )

    :ok = :gen_udp.send(socket, address, port, :inet_dns.encode(reply))
    serve(socket, test, host_answer)
  end

  defp answer("tuist.test", :ns, _host_answer), do: {0, true, [record("tuist.test", :ns, ~c"ns.tuist.test")]}
  defp answer("ns.tuist.test", :a, _host_answer), do: {0, true, [record("ns.tuist.test", :a, {127, 0, 0, 1})]}
  defp answer(@host, :a, :published), do: {0, true, [record(@host, :a, {203, 0, 113, 50})]}
  defp answer(@host, :a, :unpublished), do: {3, true, []}
  defp answer(@host, :a, :not_authoritative), do: {0, false, [record(@host, :a, {203, 0, 113, 50})]}
  defp answer(_name, _type, _host_answer), do: {0, true, []}

  defp record(name, type, data) do
    :inet_dns.make_rr(domain: String.to_charlist(name), type: type, class: :in, ttl: 60, data: data)
  end

  defp asked_through_a_resolver?(name) do
    receive do
      {:asked, ^name, _type, true} -> true
      {:asked, _name, _type, _rd} -> asked_through_a_resolver?(name)
    after
      0 -> false
    end
  end

  test "a published record is found at the zone's authoritative nameservers" do
    opts = start_nameserver(:published)

    assert :ok = DNS.record_published(@host, opts)

    assert_received {:asked, "tuist.test", :ns, true}
    assert_received {:asked, @host, :a, false}
  end

  test "a record not published yet is reported without asking a caching resolver about the host" do
    # A caching resolver would keep the answer that the host does not exist for
    # the zone's negative TTL, well past the record being published.
    opts = start_nameserver(:unpublished)

    assert {:error, :not_published} = DNS.record_published(@host, opts)

    refute asked_through_a_resolver?(@host)
  end

  test "an answer without the authoritative flag is not taken as the record being published" do
    # What a network that intercepts DNS answers with: a resolver's answer, not
    # the zone's.
    opts = start_nameserver(:not_authoritative)

    assert {:error, reason} = DNS.record_published(@host, opts)
    assert reason != :not_published
  end

  test "the zone's nameservers are found once and reused across calls" do
    # Three sequential lookups with a one-second budget each, on a path that
    # polls twice a second per instance coming up, aimed at the zone's real
    # authoritative nameservers.
    opts = start_nameserver(:published)

    assert :ok = DNS.record_published(@host, opts)
    assert_received {:asked, "tuist.test", :ns, true}
    assert_received {:asked, "ns.tuist.test", :a, true}
    assert_received {:asked, @host, :a, false}

    assert :ok = DNS.record_published(@host, opts)

    refute_received {:asked, "tuist.test", :ns, _rd}
    refute_received {:asked, "ns.tuist.test", :a, _rd}
    assert_received {:asked, @host, :a, false}
  end

  test "a zone whose nameservers cannot be found is asked about again" do
    # Caching the failure would leave every later call falling back to the
    # pod's resolver, whose negative answers are what this module exists to
    # keep out of the path.
    opts = start_nameserver(:published)
    unknown = "app.nowhere.test"

    assert {:error, _reason} = DNS.record_published(unknown, opts)
    assert_received {:asked, "nowhere.test", :ns, true}

    assert {:error, _reason} = DNS.record_published(unknown, opts)
    assert_received {:asked, "nowhere.test", :ns, true}
  end

  test "a host outside public DNS resolves through the pod's resolver" do
    assert :ok = DNS.record_published("localhost")
    assert :ok = DNS.record_published("127.0.0.1")
  end
end
