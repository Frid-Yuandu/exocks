defmodule Server.Handler do
  @moduledoc """
  This module handles the proxy procedure of each connection.
  
  ## Features
  It controls the primary connection to negotiate and authenticate with the
  client, act as a proxy agent and forward data between the client and the
  destination.
  
  ## Life Cycle
  It starts by accepting the connection from the client until the end of the
  whole proxy procedure. If the udp mode is chosen, it will wait until the end
  of this procedure.
  """
  use GenServer
  import Helper, only: [inspect_peername: 1, validate_length: 2]
  require Logger

  @socks_ver 0x05

  @tcp 0x01
  @bind 0x02
  @udp_associate 0x03
  @ipv4 0x01
  @domain 0x03
  @ipv6 0x04

  @support_cmd [@tcp]

  @request_succeeded 0x00
  # @server_failure 0x01
  @network_unreachable 0x03
  @host_unreachable 0x04
  @cmd_not_support 0x07

  @server_addr Application.compile_env(:server, :local_address)
  @server_port Application.compile_env(:server, :local_port)
  @timeout 5 * 1000

  @type handler() :: %{
          client: port(),
          dst: port()
        }

  @spec start_link(keyword(port())) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  # Callbacks

  @impl true
  @spec init(keyword()) :: {:ok, %{client: nil, destination: nil, proxy_state: :not_available}}
  def init(_args) do
    {:ok,
     %{
       client: nil,
       destination: nil,
       proxy_state: :not_available
     }}
  end

  @impl true
  def handle_cast({:bind, client}, state) do
    Logger.debug("initialize handler for client: #{inspect_peername(client)}")
    {:noreply, %{state | client: client, proxy_state: :available}}
  end

  # negotiate
  @impl true
  def handle_info(
        {:tcp, _from, <<@socks_ver, len, methods::binary>> = req},
        %{client: client, state: :available} = state
      )
      when byte_size(req) >= 3 and
             byte_size(methods) == len do
    Logger.debug("receive negotiate request: #{req |> inspect}")

    with :ok <-
           methods
           |> Server.Negotiator.new()
           |> Server.Negotiator.negotiate(client) do
      Logger.info("negotiate successfully")
      {:noreply, %{state | proxy_state: :negotiated}}
    else
      :method_unacceptable ->
        Logger.info("negotiate methods not acceptable")
        {:stop, :normal, state}

      {:error, reason} ->
        Logger.error(reason: reason, from: "negotiate")
        {:stop, :normal, state}
    end
  end

  # request
  @impl true
  def handle_info(
        {:tcp, _from, <<@socks_ver, cmd, 0x00, atype, addr_port::binary>>},
        %{client: client, proxy_state: :negotiated} = state
      )
      when cmd in @support_cmd and
             byte_size(addr_port) >= 3 and
             atype in [@ipv4, @ipv6, @domain] do
    with {addr, port} when addr != :error <- extract_addr_port(addr_port, atype),
         Logger.debug("receive proxy request, destination: #{inspect_peername({addr, port})}"),
         {:conn_dst, {:ok, dst}} <-
           {:conn_dst,
            :gen_tcp.connect(addr, port, [:binary, active: true, reuseaddr: true], @timeout)},
         :ok <- reply(client, @request_succeeded) do
      Logger.info("connect to request destination successfully")
      send(self(), :forward)
      {:noreply, %{state | destination: dst}, {:continue, :spawn_forwarder}}
    else
      {:ok, <<@socks_ver, cmd, _::binary>>} when cmd in [@bind, @udp_associate] ->
        reply(client, @cmd_not_support)
        {:error, :cmd_not_support, state}

      {:ok, <<ver, _::binary>>} when ver != @socks_ver ->
        {:error, :invalid_version, state}

      {:ok, <<_::binary>>} ->
        {:error, :invalid_packet, state}

      {:recv_req, {:error, :timeout}} ->
        {:error, :no_request, state}

      {:conn_dst, {:error, :timeout}} ->
        reply(client, @host_unreachable)
        {:error, :host_unreach, state}

      {:error, reason} ->
        reply(client, @network_unreachable)
        {:error, reason, state}
    end
  end

  def handle_continue(:spawn_forwarder, state) do
    # TODO: implement me!
  end

  @impl true
  # when to spawn a new process to forward?
  def handle_info(
        :forward,
        %{client: client, destination: dst, proxy_state: :connected} = state
      ) do
    Logger.debug("start communicating with destination")
    spawn(__MODULE__, :forward, [dst, client])
    forward(client, dst)
    {:stop, :normal, state}
  end

  def handle_info({:tcp, :error, err_msg}, state) do
    Logger.error(err_msg)
    {:stop, :normal, state}
  end

  def handle_info({:tcp, :closed, _}, state) do
    {:stop, :normal, state}
  end

  @spec reply(port(), integer()) :: :ok | {:error, any()}
  def reply(sock, rep) do
    :gen_tcp.send(
      sock,
      <<@socks_ver, rep, 0x00, @ipv4>> <> bind_addr() <> <<@server_port::16>>
    )
  end

  @spec bind_addr() :: binary()
  defp bind_addr do
    @server_addr |> Tuple.to_list() |> :binary.list_to_bin()
  end

  @spec forward(port(), port()) :: :ok
  def forward(dst, src) do
    with {:ok, packet} <- :gen_tcp.recv(src, 0),
         :ok <- :gen_tcp.send(dst, packet) do
      forward(dst, src)
    else
      {:error, :closed} ->
        :gen_tcp.shutdown(dst, :write)
        :gen_tcp.close(src)

      {:error, {:timeout, _}} ->
        Logger.warning("forward timeout")
    end
  end

  @spec extract_addr_port(binary(), integer()) ::
          {tuple() | charlist(), integer()} | {:error, :invalid_packet}
  def extract_addr_port(bin, atype) when is_binary(bin) and atype in [@ipv4, @ipv6] do
    {parse_addr(bin, :ip), parse_port(bin)}
  end

  def extract_addr_port(<<len, url_port::binary>>, atype) when atype == @domain do
    if validate_length(url_port, len + 2) do
      {parse_addr(url_port, :domain), parse_port(url_port)}
    else
      {:error, :invalid_packet}
    end
  end

  @spec parse_addr(binary(), :ip | :domain) :: tuple() | charlist()
  defp parse_addr(bin, :domain), do: bin |> :binary.part(0, byte_size(bin) - 2) |> to_charlist

  defp parse_addr(bin, :ip) do
    {:ok, addr} =
      bin
      |> :binary.bin_to_list(0, byte_size(bin) - 2)
      |> Enum.join(".")
      |> to_charlist
      |> :inet.parse_address()

    addr
  end

  def parse_port(bin), do: bin |> :binary.part(byte_size(bin), -2) |> :binary.decode_unsigned()
end
