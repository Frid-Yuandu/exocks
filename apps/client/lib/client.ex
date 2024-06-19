defmodule Client do
  @moduledoc """
  Documentation for `Client`.
  """
  use GenServer
  require Logger

  @client_port Application.compile_env(:client, :local_port)
  @accept_duration 1 * 1000

  def start_link(_args) do
    Logger.debug("starting client...")
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def stop do
    Logger.debug("stopping client...")
    GenServer.stop(__MODULE__)
  end

  @impl GenServer
  def init(_args) do
    {:ok, %{listen_socket: nil}, {:continue, :listen}}
  end

  @impl GenServer
  def handle_continue(:listen, state) do
    opts = [:binary, active: :once, reuseaddr: true]
    {:ok, socket} = :gen_tcp.listen(@client_port, opts)
    Logger.debug("listening local client_port: #{@client_port}")
    send(self(), :accept)
    {:noreply, %{state | listen_socket: socket}}
  end

  @impl GenServer
  def handle_info(:accept, %{listen_socket: ls} = state) do
    with {:ok, local_sock} <- :gen_tcp.accept(ls, @accept_duration) do
      Logger.debug("accept local socket")
      {:ok, pid} = Client.Handler.start_link(local_socket: local_sock)
      :gen_tcp.controlling_process(local_sock, pid)
    end

    send(self(), :accept)
    {:noreply, state}
  end
end
