defmodule Example.StatusLed do
  @moduledoc """
  Status LED indicator for Matter device state.

  Supports multiple display modes:
  - `:off` - LED off
  - `:on` - LED solid on (normal operation)
  - `:pairing` - Slow blink (commissioning window open)
  - `:reset` - Fast blink (factory reset in progress)
  - `:error` - Triple flash pattern

  ## Hardware Setup

      GPIO pin ---- 330Ω resistor ---- LED (+) ---- LED (-) ---- GND

  ## Configuration

      config :example,
        status_led_pin: 17  # BCM GPIO 17 (physical pin 11)
  """

  use GenServer
  require Logger

  # Blink intervals (milliseconds)
  @blink_slow 1000
  @blink_fast 250
  @flash_duration 100

  defstruct [:gpio, :gpio_pin, :mode, :led_state, :timer]

  # Client API

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Set the LED display mode.

  ## Modes
  - `:off` - LED off
  - `:on` - LED solid on
  - `:pairing` - Slow blink (0.5 Hz)
  - `:reset` - Fast blink (2 Hz)
  - `:error` - Triple flash then off
  """
  def set_mode(server \\ __MODULE__, mode) do
    GenServer.cast(server, {:set_mode, mode})
  end

  @doc """
  Quick flash to acknowledge input.
  """
  def flash(server \\ __MODULE__) do
    GenServer.cast(server, :flash)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    gpio_pin = Keyword.fetch!(opts, :gpio_pin)

    state = %__MODULE__{
      gpio_pin: gpio_pin,
      mode: :off,
      led_state: 0,
      timer: nil
    }

    # Try to open GPIO
    case open_gpio(gpio_pin) do
      {:ok, gpio} ->
        Logger.info("StatusLed: Controlling GPIO #{gpio_pin}")
        {:ok, %{state | gpio: gpio}}

      {:error, reason} ->
        Logger.warning("StatusLed: GPIO not available (#{inspect(reason)}), running in simulation mode")
        {:ok, state}
    end
  end

  @impl true
  def handle_cast({:set_mode, mode}, state) do
    Logger.debug("StatusLed: Mode changed to #{mode}")

    # Cancel existing timer
    if state.timer, do: Process.cancel_timer(state.timer)

    # Apply new mode
    new_state = %{state | mode: mode, timer: nil}
    new_state = apply_mode(new_state)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:flash, state) do
    # Quick flash without changing mode
    set_led(state, 1)
    Process.send_after(self(), :end_flash, @flash_duration)
    {:noreply, state}
  end

  @impl true
  def handle_info(:end_flash, state) do
    # Restore LED to current mode state
    set_led(state, state.led_state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:blink, state) do
    # Toggle LED state
    new_led_state = if state.led_state == 0, do: 1, else: 0
    set_led(state, new_led_state)

    # Schedule next blink
    interval = get_blink_interval(state.mode)
    timer = Process.send_after(self(), :blink, interval)

    {:noreply, %{state | led_state: new_led_state, timer: timer}}
  end

  @impl true
  def handle_info({:error_flash, count}, state) when count > 0 do
    # Toggle for error flash pattern
    new_led_state = if state.led_state == 0, do: 1, else: 0
    set_led(state, new_led_state)

    # Schedule next flash
    Process.send_after(self(), {:error_flash, count - 1}, @flash_duration)

    {:noreply, %{state | led_state: new_led_state}}
  end

  @impl true
  def handle_info({:error_flash, 0}, state) do
    # Error flash complete, turn off
    set_led(state, 0)
    {:noreply, %{state | led_state: 0, mode: :off}}
  end

  # Private functions

  defp open_gpio(pin) do
    if Code.ensure_loaded?(Circuits.GPIO) do
      Circuits.GPIO.open(pin, :output, initial_value: 0)
    else
      {:error, :circuits_gpio_not_available}
    end
  end

  defp set_led(%{gpio: nil} = _state, value) do
    # Simulation mode - just log
    Logger.debug("StatusLed: [SIM] LED #{if value == 1, do: "ON", else: "OFF"}")
    :ok
  end

  defp set_led(%{gpio: gpio}, value) do
    Circuits.GPIO.write(gpio, value)
  end

  defp apply_mode(%{mode: :off} = state) do
    set_led(state, 0)
    %{state | led_state: 0}
  end

  defp apply_mode(%{mode: :on} = state) do
    set_led(state, 1)
    %{state | led_state: 1}
  end

  defp apply_mode(%{mode: :pairing} = state) do
    # Start slow blink
    set_led(state, 1)
    timer = Process.send_after(self(), :blink, @blink_slow)
    %{state | led_state: 1, timer: timer}
  end

  defp apply_mode(%{mode: :reset} = state) do
    # Start fast blink
    set_led(state, 1)
    timer = Process.send_after(self(), :blink, @blink_fast)
    %{state | led_state: 1, timer: timer}
  end

  defp apply_mode(%{mode: :error} = state) do
    # Start error flash pattern (6 toggles = 3 flashes)
    set_led(state, 1)
    Process.send_after(self(), {:error_flash, 5}, @flash_duration)
    %{state | led_state: 1}
  end

  defp get_blink_interval(:pairing), do: @blink_slow
  defp get_blink_interval(:reset), do: @blink_fast
  defp get_blink_interval(_), do: @blink_slow
end
