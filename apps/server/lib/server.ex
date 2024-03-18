defmodule Server do
  @moduledoc """
  Documentation for `Server`.
  """
  require Logger

  @server_addr Application.compile_env(:client, :remote_address)
  @server_port Application.compile_env(:server, :local_port)
  @timeout 30 * 1000

  @socks5_version 0x05
  @no_auth 0x00
  @no_acceptable 0xFF

  @tcp_connect 0x01
  @ipv4 0x01

  def start do
    {:ok, socket} = :gen_tcp.listen(@server_port, [:binary, active: false, reuseaddr: true])
    Logger.debug("listening local server_port: #{@server_port}, set active false")

    accept(socket)
  end

  def accept(socket) do
    {:ok, client} = :gen_tcp.accept(socket)
    pid = spawn(__MODULE__, :proxy, [client])
    :gen_tcp.controlling_process(client, pid)

    {:ok, {ip, port}} = :inet.peername(client)
    Logger.debug("accept client socket #{inspect_addr(ip)}:#{port}")

    accept(socket)
  end

  def proxy(client) do
    negotiate(client)

    # request
    # TODO: request may faild, handle error
    Logger.debug("wait for proxy request")
    {:ok, <<@socks5_version, @tcp_connect, 0x00, @ipv4, rest::binary>>} = :gen_tcp.recv(client, 0)
    <<a1, a2, a3, a4, port::16>> = rest
    Logger.debug("start request to destination: #{a1}.#{a2}.#{a3}.#{a4}:#{port}")

    dst_addr = {a1, a2, a3, a4}
    Logger.debug("try to connect to request destination #{dst_addr |> inspect_addr}")

    {:ok, dst} =
      :gen_tcp.connect(
        dst_addr,
        port,
        [:binary, active: false, reuseaddr: true],
        @timeout
      )

    Logger.info("connect to request destination successfully")

    # response to client
    bind_addr =
      @server_addr |> Tuple.to_list() |> :binary.list_to_bin()

    :ok =
      :gen_tcp.send(
        client,
        <<@socks5_version, 0x00, 0x00, 0x01>> <> bind_addr <> <<@server_port::16>>
      )

    Logger.debug("response request")

    Logger.debug("start communicating with destination")
    spawn(__MODULE__, :forward, [dst, client])
    forward(client, dst)
  end

  def negotiate(sock) do
    with {:ok, <<@socks5_version, n, rest::binary>>} <- :gen_tcp.recv(sock, 0, @timeout),
         {true, methods} <-
           {n == byte_size(rest) and @no_auth in :binary.bin_to_list(rest), rest},
         :ok <- :gen_tcp.send(sock, <<@socks5_version, @no_auth>>) do
      Logger.debug("receive negotiate methods list: #{methods |> inspect}")
      Logger.info("negotiate successfully")
      :ok
    else
      {false, rest} ->
        Logger.warning("unacceptable or invalid negotiate methods list: #{rest |> inspect}")
        :ok = :gen_tcp.send(sock, <<@socks5_version, @no_acceptable>>)
        Logger.info("refuse negotiation")
    end
  end

  def forward(dst, src) do
    with {:ok, packet} <- :gen_tcp.recv(src, 0),
         :ok <- :gen_tcp.send(dst, packet) do
      forward(src, dst)
    else
      # TODO: match {:error, :ealready} {:error, :einval}

      # the reason why `:ealready` occur is that there were two processes try to
      # operate this socket at the same time.
      {:error, :closed} ->
        Logger.debug("forward finished")

      {:error, {:timeout, _}} ->
        Logger.warning("forward timeout")
    end
  end

  defp inspect_addr(address) when is_tuple(address) do
    address
    |> Tuple.to_list()
    |> Enum.join(".")
  end
end
