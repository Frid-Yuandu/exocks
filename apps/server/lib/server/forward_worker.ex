defmodule Server.ForwardWorker do
  @moduledoc """
  This module simply forward message from the destination to the client. Before
  forwarding, `bind/2` should be called to bind client and destination sockets.
  """
  require Logger
  use GenServer

  @initial_state %{
    client: nil,
    destination: nil
  }

  def start_link() do
    GenServer.start_link(__MODULE__, [])
  end

  def bind(pid, client: client, destination: dst)
      when is_port(client) and is_port(dst) do
    GenServer.call(pid, client: client, destination: dst)
  end

  @impl true
  def init(_args) do
    {:ok, @initial_state}
  end

  @impl true
  def handle_call([client: client, destination: dst], _from, _state) do
    new_state = %{
      client: client,
      destination: dst
    }

    {:reply, new_state, new_state}
  end

  @impl true
  def handle_info(
        {:tcp, _from, msg},
        %{client: c, destination: d} = state
      )
      when not is_nil(c) and not is_nil(d) do
    case :gen_tcp.send(c, msg) do
      :ok ->
        :inet.setopts(d, active: :once)
        {:noreply, state}

      {:error, :closed} ->
        {:stop, :normal, state}

      {:error, reason} ->
        Logger.error("forward error: #{inspect(reason)}")
        {:stop, :normal, state}
    end
  end

  def handle_info({:tcp_closed, _}, state), do: {:stop, :normal, state}
  def handle_info({:tcp_error, _}, state), do: {:stop, :normal, state}
end
