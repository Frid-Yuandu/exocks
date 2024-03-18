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
  @no_acceptable 0xFF

  @tcp_connect 0x01
  @ipv4 0x01
  # @ipv6 0x04
  # @domain_name 0x03

  def start do
    {:ok, socket} = :gen_tcp.listen(@client_port, [:binary, active: false, reuseaddr: true])
    Logger.debug("listening local client_port: #{@client_port}, set active false")

    accept(socket)
  end

  @doc """
  accept loops to accept local socket, spawn a new process to handle each of them.
  """
  def accept(socket) do
    {:ok, local_sock} = :gen_tcp.accept(socket)
    pid = spawn(__MODULE__, :proxy, [local_sock])
    :gen_tcp.controlling_process(local_sock, pid)

    Logger.debug("accept local socket")

    accept(socket)
  end

  def proxy(local_sock) do
    Logger.debug("try to connect to remote proxy server
      #{@server_address |> inspect_addr}:#{@server_port}")

    # TODO: report and handle error can not connect to proxy server
    {:ok, server} =
      :gen_tcp.connect(
        @server_address,
        @server_port,
        [:binary, active: false, reuseaddr: true],
        @timeout
      )

    Logger.info("connect to proxy server successfully")

    Logger.debug("start negotiate with proxy server")
    :ok = negotiate(server)

    # request
    Logger.debug("wait for proxy request")
    {:ok, dst} = :gen_tcp.recv(local_sock, 0)
    Logger.debug("start request to destination: #{dst |> inspect_addr}:443")

    :ok =
      :gen_tcp.send(
        server,
        <<@socks5_version, @tcp_connect, 0x00, @ipv4>> <> dst <> <<443::16>>
      )

    Logger.debug("send request to proxy server")

    {:ok, <<@socks5_version, 0x00, 0x00, 0x01, rest::binary>> = r_response} =
      :gen_tcp.recv(server, 0, @timeout)

    Logger.debug("receive request response from proxy server #{inspect(r_response)}")
    <<a1, a2, a3, a4, port::16>> = rest

    Logger.debug("bind address and port:
        address: #{a1}.#{a2}.#{a3}.#{a4}, port: #{port}")

    ^rest = pack_ipv4(@server_address) <> <<@server_port::16>>
    Logger.info("request successfully")

    Logger.debug("start communicating with destination")
    spawn(__MODULE__, :forward, [server, local_sock])
    forward(local_sock, server)
  end

  def negotiate(sock) do
    with :ok <- :gen_tcp.send(sock, <<@socks5_version, 1, @no_auth>>),
         Logger.debug("negotiate with proxy server, methods list: [no_auth]"),
         {:ok, <<@socks5_version, @no_auth>>} <- :gen_tcp.recv(sock, 0, @timeout) do
      Logger.info("negotiate successfully")
      :ok
    else
      {:ok, <<@socks5_version, @no_acceptable>>} ->
        Logger.error(%{
          reason: "server does not accept methods",
          from: "negotiation receive response"
        })

        :stop

      {:ok, <<_, _rest::binary>>} ->
        Logger.error(%{
          reason: "invalid socks version",
          from: "negotiation receive response"
        })

        :stop

      {:error, {:timeout, _}} ->
        Logger.error(%{
          reason: "send request timeout",
          from: "negotiation send request"
        })

        {:retry, 3}

      {:error, :timeout} ->
        Logger.error("negotiate failed: receive negotiation response timeout")
        {:retry, 3}

      {:error, reason} ->
        Logger.error("negotiate failed: #{inspect(reason)}")
        :stop
    end
  end

  def forward(dst, src) do
    with {:ok, packet} <- :gen_tcp.recv(src, 0),
         :ok <- :gen_tcp.send(dst, packet) do
      forward(src, dst)
    else
      {:error, :closed} ->
        Logger.debug("forward finished")

      {:error, {:timeout, _}} ->
        Logger.debug("forward timeout")
    end
  end

  defp pack_ipv4(address) when is_tuple(address) do
    address
    |> Tuple.to_list()
    |> Enum.map(&<<&1>>)
    |> Enum.reduce(fn acc, x -> x <> acc end)
  end

  defp inspect_addr(address) when is_tuple(address) do
    address
    |> Tuple.to_list()
    |> Enum.join(".")
  end

  defp inspect_addr(address) when is_binary(address) do
    address
    |> :binary.bin_to_list()
    |> Enum.join(".")
  end
end
