defmodule Helper do
  @spec inspect_peername(peer) :: binary()
        when peer: port() | {ip | domain_name, non_neg_integer()},
             ip: {non_neg_integer()},
             domain_name: charlist()
  def inspect_peername({ip, port})
      when tuple_size(ip) == 4 do
    (ip |> Tuple.to_list() |> Enum.join(".")) <> ":" <> to_string(port)
  end

  def inspect_peername({ip, port})
      when tuple_size(ip) == 8 do
    "[" <> (ip |> Tuple.to_list() |> Enum.join(".")) <> "]:" <> to_string(port)
  end

  def inspect_peername({url, port}) when is_list(url) do
    to_string(url) <> ":" <> to_string(port)
  end

  def inspect_peername(sock) when is_port(sock) do
    {:ok, peername} = :inet.peername(sock)
    inspect_peername(peername)
  end

  @ipv4 0x01
  @domain 0x03
  @ipv6 0x04

  @spec extract_addr_port(binary()) ::
          {ip | domain_name, integer()}
        when ip: {non_neg_integer()},
             domain_name: charlist()
  def extract_addr_port(<<
        @ipv4,
        ipv4_binary::bytes-size(4),
        port::16
      >>) do
    {to_ip_address(ipv4_binary), port}
  end

  def extract_addr_port(<<
        @ipv6,
        ipv6_binary::bytes-size(16),
        port::16
      >>) do
    {to_ip_address(ipv6_binary), port}
  end

  def extract_addr_port(<<
        @domain,
        len,
        domain_name::bytes-size(len),
        port::16
      >>) do
    {to_charlist(domain_name), port}
  end

  @spec to_ip_address(binary()) :: {non_neg_integer()}
  def to_ip_address(ip_binary) when byte_size(ip_binary) == 4 do
    for <<b::8 <- ip_binary>> do
      b
    end
    |> List.to_tuple()
  end

  def to_ip_address(ip_binary) when byte_size(ip_binary) == 16 do
    for <<b::16 <- ip_binary>> do
      b
    end
    |> List.to_tuple()
  end
end
