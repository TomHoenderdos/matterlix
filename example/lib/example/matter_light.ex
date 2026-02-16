defmodule Example.MatterLight do
  @moduledoc """
  Matter light device handler.

  Implements `Matterlix.Handler` to react to attribute changes from Matter
  controllers. When a controller toggles the On/Off attribute, this module
  logs the state change and updates the status LED.

  ## Matter Device Configuration

  The device uses test vendor ID 0xFFF1 which is reserved for development.
  For production, you need a valid vendor ID from the Connectivity Standards Alliance.
  """

  @behaviour Matterlix.Handler

  use GenServer
  require Logger

  # Matter cluster and attribute IDs
  @on_off_cluster 0x0006
  @on_off_attribute 0x0000

  # Device configuration
  @vendor_id 0xFFF1
  @product_id 0x8001
  @software_version 1
  @serial_number "MATTERLIX001"

  defstruct [:matter_server, :status_led, :light_on]

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Get the current light state."
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  # Matterlix.Handler callbacks

  @impl Matterlix.Handler
  def handle_attribute_change(_endpoint, @on_off_cluster, @on_off_attribute, _type, value) do
    light_on = value == true

    if light_on do
      Logger.info("MatterLight: Light turned ON")
    else
      Logger.info("MatterLight: Light turned OFF")
    end

    # In a real device, you would control a relay or LED strip here
    GenServer.cast(__MODULE__, {:update_light, light_on})
    :ok
  end

  def handle_attribute_change(endpoint, cluster, attribute, type, value) do
    Logger.debug(
      "MatterLight: Attribute changed - endpoint=#{endpoint}, cluster=0x#{Integer.to_string(cluster, 16)}, " <>
        "attribute=0x#{Integer.to_string(attribute, 16)}, type=#{type}, value=#{inspect(value)}"
    )

    :ok
  end

  # Server Callbacks

  @impl GenServer
  def init(opts) do
    matter_server = Keyword.fetch!(opts, :matter_server)
    status_led = Keyword.get(opts, :status_led)

    state = %__MODULE__{
      matter_server: matter_server,
      status_led: status_led,
      light_on: false
    }

    # Give Matter server time to initialize, then configure
    Process.send_after(self(), :configure_device, 2000)

    {:ok, state}
  end

  @impl GenServer
  def handle_info(:configure_device, state) do
    Logger.info("MatterLight: Configuring device...")

    # Set device identification
    case Matterlix.Matter.set_device_info(state.matter_server,
           vid: @vendor_id,
           pid: @product_id,
           version: @software_version,
           serial: @serial_number
         ) do
      :ok ->
        Logger.info("MatterLight: Device info configured")

      {:error, reason} ->
        Logger.warning("MatterLight: Failed to set device info: #{inspect(reason)}")
    end

    # Get and display pairing information
    case Matterlix.Matter.get_setup_payload(state.matter_server) do
      {:ok, payload} ->
        Logger.info("=" |> String.duplicate(60))
        Logger.info("MATTER DEVICE READY FOR PAIRING")
        Logger.info("=" |> String.duplicate(60))
        Logger.info("")
        Logger.info("QR Code: #{payload.qr_code}")
        Logger.info("")
        Logger.info("Manual Pairing Code: #{payload.manual_code}")
        Logger.info("")
        Logger.info("Press the pairing button to open commissioning window")
        Logger.info("=" |> String.duplicate(60))

        # Set LED to solid on (ready state)
        if state.status_led do
          Example.StatusLed.set_mode(state.status_led, :on)
        end

      {:error, reason} ->
        Logger.error("MatterLight: Failed to get setup payload: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:update_light, light_on}, state) do
    {:noreply, %{state | light_on: light_on}}
  end

  @impl GenServer
  def handle_call(:get_state, _from, state) do
    {:reply, %{light_on: state.light_on}, state}
  end
end
