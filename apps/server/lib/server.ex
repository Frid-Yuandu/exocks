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
    Logger.debug("starting server...")
    pid = spawn(&run/0)
    Logger.debug("server has started")
    send(pid, :listen)
    pid
  end

  def stop(pid) do
    Logger.debug("stop server")
    send(pid, :stop)
    :ok
  end

  def run(sock \\ nil) do
    receive do
      {:accept, socket} ->
        accept(socket)
        socket

      :listen ->
        listen()
        sock

      :stop ->
        :gen_tcp.close(sock)
        Logger.debug("server stop listenning")
        sock
    end
    |> run()
  end

  def listen() do
    {:ok, socket} = :gen_tcp.listen(@server_port, [:binary, active: false, reuseaddr: true])
    Logger.debug("listening local server_port: #{@server_port}, set active false")
    send(self(), {:accept, socket})
  end

  def accept(socket) do
    {:ok, client} = :gen_tcp.accept(socket)
    pid = spawn(__MODULE__, :proxy, [client])
    :gen_tcp.controlling_process(client, pid)

    Logger.debug("accept client socket from#{inspect_peername(client)}")

    send(self(), {:accept, socket})
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
    with {:ok, <<@socks5_version, n, rest::binary>> = req} <- :gen_tcp.recv(sock, 0, @timeout),
         Logger.debug("receive negotiate request: #{req |> inspect}"),
         true <- validate_methods(n, rest),
         :ok <- :gen_tcp.send(sock, <<@socks5_version, @no_auth>>) do
      Logger.info("negotiate successfully")
      :ok
    else
      {:ok, <<version, _::binary>>} ->
        Logger.debug("invalid negotiate version: #{version}")
        :ok = :gen_tcp.send(sock, <<@socks5_version, @no_acceptable>>)

      false ->
        :ok = :gen_tcp.send(sock, <<@socks5_version, @no_acceptable>>)

      {:error, :timeout} ->
        Logger.warning(reason: "receive timeout", from: "negotiate receive request")

      # TODO: do sth.

      {:error, {:timeout, _}} ->
        Logger.error(reason: "send request timeout", from: "negotiate send response")
        {:retry, 3}
    end
  end

  def forward(dst, src) do
    with Logger.debug("receive from #{inspect_peername(src)}"),
         {:receive, {:ok, packet}} <- {:receive, :gen_tcp.recv(src, 0)},
         Logger.debug("send to #{inspect_peername(dst)}"),
         {:send, :ok} <- {:send, :gen_tcp.send(dst, packet)} do
      forward(dst, src)
    else
      # TODO: match {:error, :einval}
      {_, {:error, :closed}} ->
        Logger.debug("forward finished")

      {:send, {:error, {:timeout, _}}} ->
        Logger.warning("forward timeout")
    end
  end

  def validate_methods(len, methods)
      when is_integer(len) and is_binary(methods) do
    if len != byte_size(methods) or
         @no_auth not in :binary.bin_to_list(methods) do
      Logger.debug("unacceptable negotiate methods, len: #{len}, methods: #{methods |> inspect}")
      false
    else
      true
    end
  end

  defp inspect_peername({ip, port})
       when is_tuple(ip) and is_integer(port) do
    (ip |> Tuple.to_list() |> Enum.join(".")) <> ":" <> to_string(port)
  end

  defp inspect_peername(sock) do
    {:ok, peername} = :inet.peername(sock)
    inspect_peername(peername)
  end
end
