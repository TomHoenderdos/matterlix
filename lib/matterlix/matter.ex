defmodule Matterlix.Matter do
  @moduledoc """
  High-level Elixir API for Matter SDK integration.

  This module provides a GenServer-based interface for managing a Matter device.
  It handles initialization, state management, and provides a clean API for
  interacting with Matter clusters and attributes.

  ## Example

      # Start the Matter server
      {:ok, pid} = Matterlix.Matter.start_link()

      # Get device info
      {:ok, info} = Matterlix.Matter.get_info(pid)

      # Set an attribute (e.g., turn on a light)
      :ok = Matterlix.Matter.set_attribute(pid, 1, 0x0006, 0x0000, true)

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

  alias Matterlix.Matter.NIF

  # WiFi commissioning configuration
  @wifi_interface "wlan0"
  @wifi_connect_timeout 30_000

  defstruct [:context, :started, :pending_wifi_connect]

  @type t :: %__MODULE__{
          context: reference() | nil,
          started: boolean(),
          pending_wifi_connect: reference() | nil
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
  @spec set_attribute(
          GenServer.server(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          term()
        ) ::
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

  @doc """
  Open the commissioning window to allow Matter controllers to pair with this device.

  ## Parameters
  - `server` - The GenServer pid or name
  - `timeout_seconds` - How long the window stays open (default: 300 = 5 minutes)

  ## Example

      :ok = Matterlix.Matter.open_commissioning_window(pid, 300)
  """
  @spec open_commissioning_window(GenServer.server(), non_neg_integer()) :: :ok | {:error, term()}
  def open_commissioning_window(server, timeout_seconds \\ 300) do
    GenServer.call(server, {:open_commissioning_window, timeout_seconds})
  end

  @doc """
  Get the setup payload containing QR code and manual pairing code.

  Returns a map with `:qr_code` and `:manual_code` keys.

  ## Example

      {:ok, payload} = Matterlix.Matter.get_setup_payload(pid)
      IO.puts("Scan this QR code: \#{payload.qr_code}")
      IO.puts("Or enter manually: \#{payload.manual_code}")
  """
  @spec get_setup_payload(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def get_setup_payload(server) do
    GenServer.call(server, :get_setup_payload)
  end

  @doc """
  Perform a factory reset, clearing all commissioning data and fabric info.

  **Warning**: This will unpair the device from all controllers.
  """
  @spec factory_reset(GenServer.server()) :: :ok | {:error, term()}
  def factory_reset(server) do
    GenServer.call(server, :factory_reset)
  end

  @doc """
  Set device identification info (Vendor ID, Product ID, etc.).

  Should be called before starting the Matter server.

  ## Options
  - `:vid` - Vendor ID (required, use 0xFFF1 for testing)
  - `:pid` - Product ID (required)
  - `:version` - Software version (default: 1)
  - `:serial` - Serial number string (default: "000000")

  ## Example

      :ok = Matterlix.Matter.set_device_info(pid,
        vid: 0xFFF1,
        pid: 0x8001,
        version: 1,
        serial: "DEVICE001"
      )
  """
  @spec set_device_info(GenServer.server(), keyword()) :: :ok | {:error, term()}
  def set_device_info(server, opts) do
    GenServer.call(server, {:set_device_info, opts})
  end

  @doc """
  Set commissioning credentials (setup PIN and discriminator).

  Must be called **before** `start_server/1` for the values to take effect.
  These values determine the pairing code you'll use to commission the device.

  ## Parameters
  - `server` - The GenServer pid or name
  - `setup_pin` - The setup PIN code (8 digits, 1-99999998)
  - `discriminator` - 12-bit discriminator (0-4095)

  ## Common Test Values
  - PIN: 20202021 (Matter SDK default test PIN)
  - Discriminator: 3840 (0xF00)

  ## Example

      # Set fixed commissioning credentials
      :ok = Matterlix.Matter.set_commissioning_info(pid, 20202021, 3840)

      # Then start the server
      :ok = Matterlix.Matter.start_server(pid)

      # Get the pairing codes to use
      {:ok, payload} = Matterlix.Matter.get_setup_payload(pid)
      IO.puts("Manual code: \#{payload.manual_code}")
  """
  @spec set_commissioning_info(GenServer.server(), non_neg_integer(), non_neg_integer()) ::
          :ok | {:error, term()}
  def set_commissioning_info(server, setup_pin, discriminator) do
    GenServer.call(server, {:set_commissioning_info, setup_pin, discriminator})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    auto_start = Keyword.get(opts, :auto_start, false)

    case NIF.nif_init() do
      {:ok, context} ->
        # Register this process to receive Matter events from NIF
        NIF.nif_register_callback(context)

        # Apply commissioning config if set (setup_pin and discriminator)
        setup_pin = Application.get_env(:matterlix, :setup_pin)
        discriminator = Application.get_env(:matterlix, :discriminator)

        if setup_pin && discriminator do
          Logger.info(
            "Matter: Applying configured commissioning info (PIN: #{setup_pin}, discriminator: #{discriminator})"
          )

          NIF.nif_set_commissioning_info(context, setup_pin, discriminator)
        end

        # Subscribe to WiFi connection status changes (on target only)
        if Code.ensure_loaded?(VintageNet) do
          VintageNet.subscribe(["interface", @wifi_interface, "connection"])
        end

        state = %__MODULE__{context: context, started: false, pending_wifi_connect: nil}

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

  # Handle add_network from Matter SDK - just log, credentials are stored in NIF
  @impl true
  def handle_info({:add_network, ssid, _credentials}, state) do
    Logger.info("Matter: Network credentials received for SSID: #{inspect(ssid)}")
    {:noreply, state}
  end

  # Handle connect_network from Matter SDK - trigger VintageNet WiFi connection
  @impl true
  def handle_info({:connect_network, ssid, credentials}, state) do
    ssid_str = to_string(ssid)
    psk_str = to_string(credentials)

    Logger.info("Matter: Connecting to WiFi network: #{ssid_str}")

    if Code.ensure_loaded?(VintageNetWiFi) do
      # Configure WiFi with VintageNet
      case VintageNetWiFi.quick_configure(ssid_str, psk_str) do
        :ok ->
          Logger.info("Matter: WiFi configuration applied, waiting for connection...")
          # Set timeout for connection attempt
          timer_ref = Process.send_after(self(), :wifi_connect_timeout, @wifi_connect_timeout)
          {:noreply, %{state | pending_wifi_connect: timer_ref}}

        {:error, reason} ->
          Logger.error("Matter: Failed to configure WiFi: #{inspect(reason)}")
          NIF.nif_wifi_connect_result(state.context, 1)
          {:noreply, state}
      end
    else
      # Host mode - simulate success
      Logger.info("Matter: VintageNet not available (host mode), simulating success")
      NIF.nif_wifi_connect_result(state.context, 0)
      {:noreply, state}
    end
  end

  # Handle VintageNet connection status changes
  @impl true
  def handle_info(
        {VintageNet, ["interface", @wifi_interface, "connection"], _old, new, _meta},
        state
      ) do
    case {new, state.pending_wifi_connect} do
      {:internet, timer_ref} when timer_ref != nil ->
        # Connected to internet - success!
        Process.cancel_timer(timer_ref)
        Logger.info("Matter: WiFi connected successfully (internet)")
        NIF.nif_wifi_connect_result(state.context, 0)
        {:noreply, %{state | pending_wifi_connect: nil}}

      {:lan, timer_ref} when timer_ref != nil ->
        # Connected to LAN - also success for Matter commissioning
        Process.cancel_timer(timer_ref)
        Logger.info("Matter: WiFi connected successfully (LAN)")
        NIF.nif_wifi_connect_result(state.context, 0)
        {:noreply, %{state | pending_wifi_connect: nil}}

      {:disconnected, _} ->
        Logger.debug("Matter: WiFi disconnected")
        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  # Handle connection timeout
  @impl true
  def handle_info(:wifi_connect_timeout, state) do
    if state.pending_wifi_connect do
      Logger.error("Matter: WiFi connection timeout")
      NIF.nif_wifi_connect_result(state.context, 1)
    end

    {:noreply, %{state | pending_wifi_connect: nil}}
  end

  # Catch-all for other VintageNet messages
  @impl true
  def handle_info({VintageNet, _property, _old, _new, _meta}, state) do
    {:noreply, state}
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
  def handle_call({:open_commissioning_window, timeout_seconds}, _from, state) do
    result = NIF.nif_open_commissioning_window(state.context, timeout_seconds)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:get_setup_payload, _from, state) do
    result = NIF.nif_get_setup_payload(state.context)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:factory_reset, _from, state) do
    result = NIF.nif_factory_reset(state.context)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:set_device_info, opts}, _from, state) do
    vid = Keyword.fetch!(opts, :vid)
    pid = Keyword.fetch!(opts, :pid)
    version = Keyword.get(opts, :version, 1)
    serial = Keyword.get(opts, :serial, "000000")

    result = NIF.nif_set_device_info(state.context, vid, pid, version, serial)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:set_commissioning_info, setup_pin, discriminator}, _from, state) do
    result = NIF.nif_set_commissioning_info(state.context, setup_pin, discriminator)
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
