defmodule Client.Handler do
  use GenServer
  import Helper, only: [inspect_peername: 1, extract_addr_port: 1]
  require Logger

  @server_address Application.compile_env(:client, :server_address)
  @server_port Application.compile_env(:client, :server_port)
  @timeout 10 * 1000

  @socks_version 0x05
  @no_auth 0x00
  # @user_pass 0x02
  @no_acceptable 0xFF

  @tcp_connect 0x01
  @ipv4 0x01
  # @domain_name 0x03
  # @ipv6 0x04

  defstruct local_socket: nil, server: nil, proxy_state: nil

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl GenServer
  def init(args) do
    local = Keyword.fetch!(args, :local_socket)

    {:ok,
     %Client.Handler{
       local_socket: local,
       proxy_state: :unavailable
     }, {:continue, :connect_to_server}}
  end

  @impl GenServer
  def handle_continue(
        :connect_to_server,
        %Client.Handler{proxy_state: :unavailable} = state
      ) do
    Logger.debug("try to connect to remote proxy server
      #{{@server_address, @server_port} |> inspect_peername}")

    case connect_to_server() do
      {:ok, server} ->
        send(self(), {:negotiate, retry: 3})

        {:noreply, %Client.Handler{state | server: server, proxy_state: :available}}

      {:error, reason} ->
        Logger.critical("fail to connect to the proxy server: #{reason}")
        {:stop, :connect_server_failed, state}
    end
  end

  defp connect_to_server do
    opts = [:binary, active: false, reuseaddr: true]
    :gen_tcp.connect(@server_address, @server_port, opts, @timeout)
  end

  @impl GenServer
  def handle_info(
        {:negotiate, retry: retry_times},
        %Client.Handler{server: server, proxy_state: :available} = state
      ) do
    with :ok <- :gen_tcp.send(server, <<@socks_version, 1, @no_auth>>),
         Logger.debug("negotiate with proxy server, methods list: [no_auth]"),
         {:ok, <<@socks_version, @no_auth>>} <- :gen_tcp.recv(server, 0, @timeout) do
      Logger.info("negotiate successfully")
      Logger.debug("waiting proxy request...")
      # :inet.setopts(server,active: :once)
      {:noreply, %Client.Handler{state | proxy_state: :negotiated}}
    else
      {:ok, <<@socks_version, @no_acceptable>>} ->
        Logger.error("negotiate failed: server does not accept negotiation")
        {:stop, :negotiate_error, state}

      {:error, {:timeout, _}} ->
        Logger.warning("negotiate failed: send methods timeout")

        if retry_times > 0 do
          send(self(), {:negotiate, retry: retry_times - 1})
          {:noreply, state}
        else
          {:stop, :negotiate_error, state}
        end

      {:error, :timeout} ->
        Logger.warning("negotiate failed: receive negotiation response timeout")

        if retry_times > 0 do
          send(self(), {:negotiate, retry: retry_times - 1})
          {:noreply, state}
        else
          {:stop, :negotiate_error, state}
        end

      {:error, reason} ->
        Logger.error("negotiate failed: #{inspect(reason)}")
        {:stop, :negotiate_error, state}

      _ ->
        Logger.error("unexpected negotiate failed")
        {:stop, :negotiate_error, state}
    end
  end

  # request

  @impl GenServer
  def handle_info(
        {:tcp, local, uri},
        %Client.Handler{
          local_socket: local,
          server: server,
          proxy_state: :negotiated
        } = state
      ) do
    dst = extract_addr_port(<<@ipv4, uri::binary>>)
    Logger.debug("request to destination: #{inspect_peername(dst)}")

    with :ok <- :gen_tcp.send(server, <<@socks_version, @tcp_connect, 0, @ipv4, uri::binary>>),
         {:ok, <<@socks_version, 0, 0, 1, _bind_uri::binary>>} <-
           :gen_tcp.recv(server, 0, @timeout) do
      Logger.info("request successfully")
      :inet.setopts(local, active: :once)
      :inet.setopts(server, active: :once)
      {:noreply, %Client.Handler{state | proxy_state: :connected}}
    end
  end

  # forward

  @impl GenServer
  def handle_info(
        {:tcp, local, msg},
        %Client.Handler{
          local_socket: local,
          server: server,
          proxy_state: :connected
        } = state
      ) do
    :ok = :gen_tcp.send(server, msg)
    :inet.setopts(local, active: :once)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(
        {:tcp, server, msg},
        %Client.Handler{
          local_socket: local,
          server: server,
          proxy_state: :connected
        } = state
      ) do
    :ok = :gen_tcp.send(local, msg)
    :inet.setopts(server, active: :once)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:tcp_error, err_msg}, state) do
    Logger.error("tcp error: #{err_msg}")
    {:stop, :normal, state}
  end

  @impl GenServer
  def handle_info({:tcp_closed, _from}, state) do
    {:stop, :normal, state}
  end
end
