defmodule MatterNerves.Matter do
  @moduledoc """
  High-level Elixir API for Matter SDK integration.

  This module provides a GenServer-based interface for managing a Matter device.
  It handles initialization, state management, and provides a clean API for
  interacting with Matter clusters and attributes.

  ## Example

      # Start the Matter server
      {:ok, pid} = MatterNerves.Matter.start_link()

      # Get device info
      {:ok, info} = MatterNerves.Matter.get_info(pid)

      # Set an attribute (e.g., turn on a light)
      :ok = MatterNerves.Matter.set_attribute(pid, 1, 0x0006, 0x0000, true)

  ## Matter Concepts

  - **Endpoint**: A functional unit on the device (e.g., endpoint 1 might be a light)
  - **Cluster**: A group of related attributes and commands (e.g., On/Off cluster)
  - **Attribute**: A piece of data within a cluster (e.g., the "on" state)

  ## Common Clusters

  | Cluster ID | Name           | Description                    |
  |------------|----------------|--------------------------------|
  | 0x0006     | On/Off         | Basic on/off control           |
  | 0x0008     | Level Control  | Dimming/brightness             |
  | 0x0300     | Color Control  | Color temperature, hue, sat    |
  | 0x0402     | Temperature    | Temperature measurement        |
  | 0x0405     | Humidity       | Relative humidity              |
  """

  use GenServer
  require Logger

  alias MatterNerves.Matter.NIF

  defstruct [:context, :started]

  @type t :: %__MODULE__{
          context: reference() | nil,
          started: boolean()
        }

  # Client API

  @doc """
  Start the Matter GenServer.

  ## Options
  - `:name` - Optional name to register the process
  - `:auto_start` - Whether to automatically start the Matter server (default: false)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Initialize and start the Matter server.

  This makes the device discoverable and commissionable on the network.
  """
  @spec start_server(GenServer.server()) :: :ok | {:error, term()}
  def start_server(server) do
    GenServer.call(server, :start_server)
  end

  @doc """
  Stop the Matter server.
  """
  @spec stop_server(GenServer.server()) :: :ok | {:error, term()}
  def stop_server(server) do
    GenServer.call(server, :stop_server)
  end

  @doc """
  Get information about the Matter device.
  """
  @spec get_info(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def get_info(server) do
    GenServer.call(server, :get_info)
  end

  @doc """
  Set a Matter attribute value.

  ## Parameters
  - `server` - The GenServer pid or name
  - `endpoint_id` - The endpoint ID (usually 1 for simple devices)
  - `cluster_id` - The cluster ID
  - `attribute_id` - The attribute ID
  - `value` - The value to set
  """
  @spec set_attribute(GenServer.server(), non_neg_integer(), non_neg_integer(), non_neg_integer(), term()) ::
          :ok | {:error, term()}
  def set_attribute(server, endpoint_id, cluster_id, attribute_id, value) do
    GenServer.call(server, {:set_attribute, endpoint_id, cluster_id, attribute_id, value})
  end

  @doc """
  Get a Matter attribute value.
  """
  @spec get_attribute(GenServer.server(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          {:ok, term()} | {:error, term()}
  def get_attribute(server, endpoint_id, cluster_id, attribute_id) do
    GenServer.call(server, {:get_attribute, endpoint_id, cluster_id, attribute_id})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    auto_start = Keyword.get(opts, :auto_start, false)

    case NIF.nif_init() do
      {:ok, context} ->
        state = %__MODULE__{context: context, started: false}

        if auto_start do
          send(self(), :auto_start)
        end

        {:ok, state}

      {:error, reason} ->
        {:stop, {:init_failed, reason}}
    end
  end

  @impl true
  def handle_info(:auto_start, state) do
    case NIF.nif_start_server(state.context) do
      :ok ->
        Logger.info("Matter server started automatically")
        {:noreply, %{state | started: true}}

      {:error, reason} ->
        Logger.error("Failed to auto-start Matter server: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_call(:start_server, _from, %{started: true} = state) do
    {:reply, {:error, :already_started}, state}
  end

  def handle_call(:start_server, _from, state) do
    case NIF.nif_start_server(state.context) do
      :ok ->
        Logger.info("Matter server started")
        {:reply, :ok, %{state | started: true}}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:stop_server, _from, %{started: false} = state) do
    {:reply, {:error, :not_started}, state}
  end

  def handle_call(:stop_server, _from, state) do
    case NIF.nif_stop_server(state.context) do
      :ok ->
        Logger.info("Matter server stopped")
        {:reply, :ok, %{state | started: false}}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:get_info, _from, state) do
    result = NIF.nif_get_info(state.context)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:set_attribute, endpoint_id, cluster_id, attribute_id, value}, _from, state) do
    result = NIF.nif_set_attribute(state.context, endpoint_id, cluster_id, attribute_id, value)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_attribute, endpoint_id, cluster_id, attribute_id}, _from, state) do
    result = NIF.nif_get_attribute(state.context, endpoint_id, cluster_id, attribute_id)
    {:reply, result, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.started do
      NIF.nif_stop_server(state.context)
    end

    :ok
  end
end
