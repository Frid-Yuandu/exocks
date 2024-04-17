defmodule Server do
  @moduledoc """
  Documentation for `Server`.
  """
  use GenServer
  require Logger
  alias Server.Handler
  import Helper, only: [inspect_peername: 1]

  @server_port Application.compile_env(:server, :local_port)
  @accept_duration 1 * 1000

  def start_link() do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def stop do
    Logger.debug("stopping server ...")
    GenServer.stop(__MODULE__)
  end

  # Callbacks

  @impl true
  def init(_args) do
    Logger.debug("starting server...")
    {:ok, %{listen_socket: nil}, {:continue, :listen}}
  end

  @impl true
  def handle_continue(:listen, state) do
    {:ok, socket} = :gen_tcp.listen(@server_port, [:binary, active: true, reuseaddr: true])
    Logger.debug("listening local server_port: #{@server_port}")
    send(self(), :accept)
    {:noreply, %{state | listen_socket: socket}}
  end

  @impl true
  def handle_info(:accept, %{listen_socket: ls} = state) do
    with {:ok, client} <- :gen_tcp.accept(ls, @accept_duration) do
      Logger.debug("accept client socket from#{inspect_peername(client)}")
      {:ok, pid} = Handler.start_link(client: client)
      :gen_tcp.controlling_process(client, pid)
    end

    send(self(), :accept)
    {:noreply, state}
  end

  # @impl true
  # def handle_info(msg, state) do
  #   Logger.error("unexpected message: #{inspect(msg)}")
  #   {:noreply, state}
  # end
end
