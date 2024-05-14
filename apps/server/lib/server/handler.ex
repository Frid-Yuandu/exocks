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
  alias Server.ForwardWorker
  alias Server.Handler
  use GenServer
  import Helper, only: [inspect_peername: 1]
  require Logger

  @socks_version 0x05
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

  @type t() :: %__MODULE__{
          client: port() | nil,
          destination: port() | nil,
          proxy_state: atom()
        }
  defstruct client: nil, destination: nil, proxy_state: nil

  @spec start_link(keyword(port())) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl GenServer
  def init(args) do
    client = Keyword.get(args, :client)

    {:ok,
     %Handler{
       client: client,
       destination: nil,
       proxy_state: :available
     }}
  end

  # negotiate
  @impl GenServer
  def handle_info(
        {:tcp, _from, <<@socks_version, len, methods::binary>> = req},
        %Handler{client: client, proxy_state: :available} = state
      )
      when byte_size(req) >= 3 and byte_size(methods) == len do
    Logger.debug("receive negotiate request: #{req |> inspect}")

    with :ok <-
           %Server.Negotiator{}
           |> Server.Negotiator.parse(methods)
           |> Server.Negotiator.negotiate(client) do
      Logger.info("negotiate successfully")
      {:noreply, %Handler{state | proxy_state: :negotiated}}
    else
      :method_unacceptable ->
        Logger.info("negotiate methods not acceptable")
        {:stop, :normal, state}

      {:error, :no_such_user, username} ->
        Logger.error(
          "negotiate error: user #{username} does not exist." <>
            "If this error occurs repeatedly, please check your userpass configuration."
        )

        {:stop, :normal, state}

      {:error, reason} ->
        Logger.warning("negotiate failure: #{inspect(reason)}")
        {:stop, :normal, state}
    end
  end

  # request
  def handle_info(
        {:tcp, _from, <<@socks_version, cmd, 0x00, address_type, uri::binary>>},
        %Handler{client: client, proxy_state: proxy_state} = state
      )
      when cmd in @support_cmd and
             byte_size(uri) >= 3 and
             address_type in [@ipv4, @ipv6, @domain] and
             proxy_state in [:negotiated, :connected] do
    with {addr, port} <-
           extract_addr_port(<<address_type, uri::binary>>),
         Logger.debug("receive proxy request, destination: #{inspect_peername({addr, port})}"),
         opts = [:binary, active: true, reuseaddr: true],
         {:conn_dst, {:ok, dst}} <-
           {:conn_dst, :gen_tcp.connect(addr, port, opts, @timeout)},
         :ok <- reply(client, @request_succeeded) do
      Logger.info("connect to request destination successfully")

      {:noreply, %Handler{state | destination: dst, proxy_state: :connected},
       {:continue, :spawn_forwarder}}
    else
      {:ok, <<@socks_version, cmd, _::binary>>} when cmd in [@bind, @udp_associate] ->
        reply(client, @cmd_not_support)
        {:error, :cmd_not_support, state}

      {:ok, <<ver, _::binary>>} when ver != @socks_version ->
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

  def handle_info(
        {:tcp, _from, msg},
        %Handler{destination: d, proxy_state: :connected} = state
      ) do
    case :gen_tcp.send(d, msg) do
      :ok ->
        {:noreply, state}

      {:error, reason} ->
        Logger.error(
          "forward message to" <>
            " [#{inspect_peername(d)}]" <>
            " error: #{inspect(reason)}"
        )

        {:stop, :normal, state}
    end
  end

  def handle_info({:tcp_error, err_msg}, state) do
    Logger.error(err_msg)
    {:stop, :normal, state}
  end

  def handle_info({:tcp_closed, _}, state), do: {:stop, :normal, state}

  @impl GenServer
  def handle_continue(:spawn_forwarder, state) do
    {:ok, pid} = ForwardWorker.start_link()

    ForwardWorker.bind(pid,
      client: state.client,
      destination: state.destination
    )

    :gen_tcp.controlling_process(state.destination, pid)
    {:noreply, state}
  end

  @spec reply(port(), integer()) :: :ok | {:error, any()}
  def reply(sock, rep) do
    :gen_tcp.send(
      sock,
      <<@socks_version, rep, 0x00, @ipv4>> <> bind_addr() <> <<@server_port::16>>
    )
  end

  @spec bind_addr() :: binary()
  defp bind_addr do
    @server_addr |> Tuple.to_list() |> :binary.list_to_bin()
  end

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
