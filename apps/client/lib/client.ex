defmodule Client do
  @moduledoc """
  Documentation for `Client`.
  """

  require Logger

  @client_port Application.compile_env(:client, :local_port)
  @server_address Application.compile_env(:client, :remote_address)
  @server_port Application.compile_env(:client, :remote_port)
  @timeout 30 * 1000

  @socks5_version 0x05
  @no_auth 0x00
  # @username_password 0x02

  @tcp_connect 0x01
  @ipv4 0x01
  # @ipv6 0x04
  # @domain_name 0x03

  def start do
    {:ok, socket} = :gen_tcp.listen(@client_port, [:binary, active: false, reuseaddr: true])
    Logger.debug("listening local client_port: #{@client_port}, set active false")
    {:ok, local_sock} = :gen_tcp.accept(socket)
    Logger.debug("accept local socket")

    Logger.debug("try to connect to remote proxy server
      #{@server_address |> inspect_addr}:#{@server_port}")

    {:ok, remote_sock} =
      :gen_tcp.connect(
        @server_address,
        @server_port,
        [:binary, active: false, reuseaddr: true],
        @timeout
      )

    Logger.info("connect to proxy server successfully")

    # negotiate
    Logger.debug("start negotiate with proxy server")
    :ok = :gen_tcp.send(remote_sock, <<@socks5_version, 1, @no_auth>>)
    {:ok, <<@socks5_version, @no_auth>>} = :gen_tcp.recv(remote_sock, 0, @timeout)
    Logger.info("negotiate successfully")

    # request
    Logger.debug("wait for proxy request")
    {:ok, dst} = :gen_tcp.recv(local_sock, 0)
    Logger.debug("start request to destination: #{dst |> inspect_addr}:443")

    :ok =
      :gen_tcp.send(
        remote_sock,
        <<@socks5_version, @tcp_connect, 0x00, @ipv4>> <> dst <> <<443::16>>
      )

    Logger.debug("send request to proxy server")

    {:ok, <<@socks5_version, 0x00, 0x00, 0x01, rest::binary>> = r_response} =
      :gen_tcp.recv(remote_sock, 0, @timeout)

    Logger.debug("receive request response from proxy server #{inspect(r_response)}")
    <<a1, a2, a3, a4, port::16>> = rest

    Logger.debug(
      "bind address and port:\n" <>
        "address: #{[a1, a2, a3, a4] |> Enum.join(".")}, port: #{port}"
    )

    ^rest = pack_ipv4(@server_address) <> <<@server_port::16>>
    Logger.info("request successfully")

    Logger.debug("start communicating with destination")
    # communicate
    spawn(__MODULE__, :send_to_local, [remote_sock, local_sock])
    send_to_remote(local_sock, remote_sock)
  end

  def send_to_local(remote_sock, local_sock) do
    {:ok, packet} = :gen_tcp.recv(remote_sock, 0)
    :ok = :gen_tcp.send(local_sock, packet)
    send_to_local(remote_sock, local_sock)
  end

  def send_to_remote(local_sock, remote_sock) do
    {:ok, packet} = :gen_tcp.recv(local_sock, 0)
    :ok = :gen_tcp.send(remote_sock, packet)
    send_to_remote(local_sock, remote_sock)
  end

  defp pack_ipv4(address) when is_tuple(address) do
    address
    |> Tuple.to_list()
    |> Enum.map(&<<&1>>)
    |> Enum.reduce(fn acc, x -> x <> acc end)
  end

  defp inspect_addr(address) when is_tuple(address) do
    address |> Tuple.to_list() |> Enum.join(".")
  end

  defp inspect_addr(address) when is_binary(address) do
    address |> to_charlist |> Enum.join(".")
  end
end
