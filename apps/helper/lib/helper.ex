defmodule Helper do
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

  def validate_length(packet, expect_len) do
    expect_len == byte_size(packet)
  end
end
