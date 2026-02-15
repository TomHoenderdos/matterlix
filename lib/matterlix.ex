defmodule Matterlix do
  @moduledoc """
  Elixir NIF bindings for the Matter SDK.

  ## Pushing data to Matter (sensors)

      Matterlix.update_attribute(1, 0x0402, 0x0000, temperature_value)

  ## Reacting to Matter events (actuators)

  Implement the `Matterlix.Handler` behaviour:

      defmodule MyApp.MatterHandler do
        @behaviour Matterlix.Handler

        @impl true
        def handle_attribute_change(1, 0x0006, 0x0000, _type, value) do
          Circuits.GPIO.write(pin, if(value, do: 1, else: 0))
          :ok
        end
      end

  Then configure it:

      config :matterlix, handler: MyApp.MatterHandler
  """

  @doc """
  Update a Matter attribute value (e.g., push a sensor reading).

  This is the primary API for Device -> Matter communication.
  The Matter SDK will notify any subscribed controllers automatically.

  ## Parameters
  - `endpoint_id` - endpoint (usually 1 for simple devices)
  - `cluster_id` - cluster ID (e.g., 0x0402 for Temperature Measurement)
  - `attribute_id` - attribute ID within the cluster
  - `value` - the value to set

  ## Example

      # Push a temperature reading (value in 0.01 C units)
      Matterlix.update_attribute(1, 0x0402, 0x0000, 2350)

      # Turn on a light
      Matterlix.update_attribute(1, 0x0006, 0x0000, true)
  """
  @spec update_attribute(non_neg_integer(), non_neg_integer(), non_neg_integer(), term()) ::
          :ok | {:error, term()}
  def update_attribute(endpoint_id, cluster_id, attribute_id, value) do
    Matterlix.Matter.set_attribute(Matterlix.Matter, endpoint_id, cluster_id, attribute_id, value)
  end

  @doc """
  Get a Matter attribute value.
  """
  @spec get_attribute(non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          {:ok, term()} | {:error, term()}
  def get_attribute(endpoint_id, cluster_id, attribute_id) do
    Matterlix.Matter.get_attribute(Matterlix.Matter, endpoint_id, cluster_id, attribute_id)
  end
end
