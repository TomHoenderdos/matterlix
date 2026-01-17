# Matterlix Example: Matter Light with GPIO Pairing

This example demonstrates how to build a Matter-compatible smart light using Matterlix with GPIO-based pairing controls.

## Features

- **Matter Light Device**: On/Off light controllable via Matter protocol
- **Pairing Button**: GPIO button to trigger commissioning and factory reset
- **Status LED**: Visual feedback for device state
- **Host Development**: Works on your development machine without hardware

## Hardware Requirements

- Raspberry Pi (3, 4, or 5 recommended)
- 1x Push button (momentary, normally open)
- 1x LED (any color)
- 1x 330Ω resistor
- Jumper wires

## Wiring Diagram

```
Raspberry Pi GPIO Header (BCM numbering):

                    ┌─────────────────┐
              3.3V  │ 1           2 │  5V
   (SDA1) GPIO 2    │ 3           4 │  5V
   (SCL1) GPIO 3    │ 5           6 │  GND ◄──┐
         GPIO 4     │ 7           8 │  GPIO 14│
              GND   │ 9          10 │  GPIO 15│
  [LED] GPIO 17 ───►│ 11         12 │  GPIO 18│
 [BTN] GPIO 27 ◄────│ 13         14 │  GND ◄──┤ (use any GND)
        GPIO 22     │ 15         16 │  GPIO 23│
              3.3V  │ 17         18 │  GPIO 24│
                    └─────────────────┘

LED Circuit:
    GPIO 17 ──── 330Ω ──── LED(+) ──── LED(-) ──── GND

Button Circuit:
    GPIO 27 ──── Button ──── GND
    (internal pull-up resistor enabled)
```

## Button Actions

| Press Duration | Action | LED Feedback |
|----------------|--------|--------------|
| < 3 seconds | Open commissioning window (5 min) | Slow blink |
| > 5 seconds | Factory reset | Fast blink |

## LED Modes

| Mode | Pattern | Meaning |
|------|---------|---------|
| Solid ON | Continuous | Device ready |
| Slow blink | 1 Hz | Commissioning window open |
| Fast blink | 4 Hz | Factory reset in progress |
| Triple flash | 3 quick flashes | Error |

## Quick Start

### Host Development (No Hardware)

```bash
cd example
mix deps.get
iex -S mix
```

In IEx, you can simulate button presses:

```elixir
# Simulate short press (opens commissioning window)
Example.PairingButton.simulate_short_press()

# Simulate long press (factory reset)
Example.PairingButton.simulate_long_press()

# Control LED manually
Example.StatusLed.set_mode(:pairing)
Example.StatusLed.set_mode(:on)
```

### Raspberry Pi Deployment

```bash
export MIX_TARGET=rpi4  # or rpi3, rpi5
mix deps.get
mix firmware
mix burn  # Insert SD card first
```

## Pairing with a Matter Controller

1. **Press the button** (short press) to open the commissioning window
2. The LED will start **blinking slowly**
3. On your Matter controller (Apple Home, Google Home, etc.):
   - Add a new device
   - Scan the QR code shown in the serial console
   - Or enter the manual pairing code
4. Once paired, the LED returns to **solid on**

## Factory Reset

1. **Press and hold the button** for more than 5 seconds
2. The LED will **blink rapidly**
3. Release the button
4. The device will reset to factory defaults

## Configuration

Edit `config/target.exs` to change GPIO pins:

```elixir
config :example,
  status_led_pin: 17,      # BCM GPIO number
  pairing_button_pin: 27   # BCM GPIO number
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Example App                          │
│  ┌──────────────┐  ┌────────────┐  ┌────────────────┐  │
│  │ MatterLight  │  │ StatusLed  │  │ PairingButton  │  │
│  │ (device      │  │ (GPIO out) │  │ (GPIO input)   │  │
│  │  logic)      │  └────────────┘  └────────────────┘  │
│  └──────────────┘                                       │
│         │                                               │
│         ▼                                               │
│  ┌─────────────────────────────────────────────────┐   │
│  │              Matterlix.Matter                    │   │
│  │         (GenServer wrapping NIF)                 │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
                    Matter SDK (NIF)
```

## Troubleshooting

### "GPIO not available" warnings on host

This is normal. The app runs in simulation mode when GPIO hardware isn't present.

### Button not responding

1. Check wiring - button should connect GPIO to GND
2. Verify GPIO pin number matches config
3. Check serial console for debug messages

### LED not lighting up

1. Check LED polarity (longer leg = positive)
2. Verify resistor is in circuit
3. Try swapping LED orientation

## License

See the main Matterlix project license.
