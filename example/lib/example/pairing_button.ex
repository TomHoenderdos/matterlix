defmodule Example.PairingButton do
  @moduledoc """
  GPIO button handler for Matter pairing modes.

  Detects button press duration to trigger different actions:
  - **Short press (< 3 sec)**: Open commissioning window for pairing
  - **Long press (> 5 sec)**: Factory reset the device

  The button is expected to be connected between the GPIO pin and GND,
  using the internal pull-up resistor (active low).

  ## Hardware Setup

      GPIO pin ----+---- Button ---- GND
                   |
              (internal pull-up)

  ## Configuration

      config :example,
        pairing_button_pin: 27  # BCM GPIO 27 (physical pin 13)
  """

  use GenServer
  require Logger

  # Press duration thresholds (milliseconds)
  @short_press_max 3_000
  @long_press_min 5_000
  @debounce_time 50

  # Commissioning window duration (seconds)
  @commissioning_timeout 300

  defstruct [:gpio, :gpio_pin, :matter_server, :status_led, :press_start, :debounce_timer]

  # Client API

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    gpio_pin = Keyword.fetch!(opts, :gpio_pin)
    matter_server = Keyword.fetch!(opts, :matter_server)
    status_led = Keyword.get(opts, :status_led)

    state = %__MODULE__{
      gpio_pin: gpio_pin,
      matter_server: matter_server,
      status_led: status_led,
      press_start: nil,
      debounce_timer: nil
    }

    # Try to open GPIO - may fail on host without hardware
    case open_gpio(gpio_pin) do
      {:ok, gpio} ->
        Logger.info("PairingButton: Listening on GPIO #{gpio_pin}")
        {:ok, %{state | gpio: gpio}}

      {:error, reason} ->
        Logger.warning("PairingButton: GPIO not available (#{inspect(reason)}), running in simulation mode")
        {:ok, state}
    end
  end

  # Button pressed (active low - value goes to 0)
  @impl true
  def handle_info({:circuits_gpio, _pin, _timestamp, 0}, state) do
    # Cancel any pending debounce timer
    if state.debounce_timer, do: Process.cancel_timer(state.debounce_timer)

    # Start debounce timer
    timer = Process.send_after(self(), :button_pressed_debounced, @debounce_time)
    {:noreply, %{state | debounce_timer: timer}}
  end

  # Button released (value goes to 1)
  @impl true
  def handle_info({:circuits_gpio, _pin, _timestamp, 1}, state) do
    # Cancel any pending debounce timer
    if state.debounce_timer, do: Process.cancel_timer(state.debounce_timer)

    if state.press_start do
      duration = System.monotonic_time(:millisecond) - state.press_start
      handle_press_duration(duration, state)
    end

    {:noreply, %{state | press_start: nil, debounce_timer: nil}}
  end

  # Debounced button press confirmed
  @impl true
  def handle_info(:button_pressed_debounced, state) do
    Logger.debug("PairingButton: Button pressed")

    # Flash LED to acknowledge press
    if state.status_led do
      Example.StatusLed.flash(state.status_led)
    end

    {:noreply, %{state | press_start: System.monotonic_time(:millisecond), debounce_timer: nil}}
  end

  # Simulation: trigger a short press from IEx
  @impl true
  def handle_cast(:simulate_short_press, state) do
    Logger.info("PairingButton: Simulating short press")
    handle_press_duration(500, state)
    {:noreply, state}
  end

  # Simulation: trigger a long press from IEx
  @impl true
  def handle_cast(:simulate_long_press, state) do
    Logger.info("PairingButton: Simulating long press")
    handle_press_duration(6_000, state)
    {:noreply, state}
  end

  # Private functions

  defp open_gpio(pin) do
    if Code.ensure_loaded?(Circuits.GPIO) do
      Circuits.GPIO.open(pin, :input, pull_mode: :pullup)
      |> case do
        {:ok, gpio} ->
          Circuits.GPIO.set_interrupts(gpio, :both)
          {:ok, gpio}

        error ->
          error
      end
    else
      {:error, :circuits_gpio_not_available}
    end
  end

  defp handle_press_duration(duration, state) when duration < @short_press_max do
    # Short press - open commissioning window
    Logger.info("PairingButton: Short press (#{duration}ms) - Opening commissioning window")

    case Matterlix.Matter.open_commissioning_window(state.matter_server, @commissioning_timeout) do
      :ok ->
        Logger.info("PairingButton: Commissioning window open for #{@commissioning_timeout} seconds")

        if state.status_led do
          Example.StatusLed.set_mode(state.status_led, :pairing)
        end

        # Schedule return to normal mode after timeout
        Process.send_after(self(), :commissioning_window_closed, @commissioning_timeout * 1000)

      {:error, reason} ->
        Logger.error("PairingButton: Failed to open commissioning window: #{inspect(reason)}")

        if state.status_led do
          Example.StatusLed.set_mode(state.status_led, :error)
        end
    end
  end

  defp handle_press_duration(duration, state) when duration >= @long_press_min do
    # Long press - factory reset
    Logger.warning("PairingButton: Long press (#{duration}ms) - FACTORY RESET!")

    if state.status_led do
      Example.StatusLed.set_mode(state.status_led, :reset)
    end

    case Matterlix.Matter.factory_reset(state.matter_server) do
      :ok ->
        Logger.warning("PairingButton: Factory reset complete - device will restart")

      {:error, reason} ->
        Logger.error("PairingButton: Factory reset failed: #{inspect(reason)}")
    end
  end

  defp handle_press_duration(duration, _state) do
    # Medium press (between short and long) - ignored
    Logger.debug("PairingButton: Medium press (#{duration}ms) - ignored")
  end

  # Public simulation functions (for testing without hardware)

  @doc """
  Simulate a short button press (opens commissioning window).
  Use from IEx: `Example.PairingButton.simulate_short_press()`
  """
  def simulate_short_press(server \\ __MODULE__) do
    GenServer.cast(server, :simulate_short_press)
  end

  @doc """
  Simulate a long button press (factory reset).
  Use from IEx: `Example.PairingButton.simulate_long_press()`
  """
  def simulate_long_press(server \\ __MODULE__) do
    GenServer.cast(server, :simulate_long_press)
  end
end
