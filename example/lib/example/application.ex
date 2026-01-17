defmodule Example.Application do
  @moduledoc """
  Example application demonstrating Matterlix with GPIO-based pairing controls.

  This application starts:
  - Matterlix.Matter GenServer for Matter protocol
  - StatusLed for visual feedback
  - PairingButton for GPIO button input
  - MatterLight as the main device logic
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    # Get GPIO pins from config (with defaults for Raspberry Pi)
    led_pin = Application.get_env(:example, :status_led_pin, 17)
    button_pin = Application.get_env(:example, :pairing_button_pin, 27)

    children =
      [
        # Matter server (named for easy access)
        {Matterlix.Matter, name: Example.Matter, auto_start: true},

        # Status LED indicator
        {Example.StatusLed, name: Example.StatusLed, gpio_pin: led_pin},

        # Pairing button handler
        {Example.PairingButton,
         name: Example.PairingButton,
         gpio_pin: button_pin,
         matter_server: Example.Matter,
         status_led: Example.StatusLed},

        # Main Matter light device logic
        {Example.MatterLight, matter_server: Example.Matter, status_led: Example.StatusLed}
      ]
      |> Enum.filter(&is_tuple/1)

    opts = [strategy: :one_for_one, name: Example.Supervisor]

    Logger.info("Starting Example application...")
    Logger.info("  LED pin: GPIO #{led_pin}")
    Logger.info("  Button pin: GPIO #{button_pin}")

    Supervisor.start_link(children, opts)
  end
end
