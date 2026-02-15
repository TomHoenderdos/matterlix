defmodule Matterlix.Handler do
  @moduledoc """
  Behaviour for handling Matter events in consuming projects.

  Implement this behaviour in your project and configure it:

      config :matterlix, handler: MyApp.MatterHandler

  ## Example

      defmodule MyApp.MatterHandler do
        @behaviour Matterlix.Handler

        @impl true
        def handle_attribute_change(endpoint_id, cluster_id, attribute_id, type, value) do
          # React to attribute changes from Matter controllers
          :ok
        end

        @impl true
        def handle_commissioning_complete(fabric_index) do
          :ok
        end
      end
  """

  @doc """
  Called when a Matter controller changes an attribute value.

  This is the primary callback — it fires when e.g. a controller toggles a light,
  changes brightness, etc.

  ## Parameters
  - `endpoint_id` — the endpoint (e.g. 1 for the first functional endpoint)
  - `cluster_id` — the cluster (e.g. 0x0006 for On/Off)
  - `attribute_id` — the attribute within the cluster (e.g. 0x0000 for OnOff)
  - `type` — the ZCL attribute type as an integer
  - `value` — the new value (boolean, integer, or nil for unsupported types)
  """
  @callback handle_attribute_change(
              endpoint_id :: non_neg_integer(),
              cluster_id :: non_neg_integer(),
              attribute_id :: non_neg_integer(),
              type :: non_neg_integer(),
              value :: boolean() | integer() | nil
            ) :: :ok | {:error, term()}

  @doc """
  Called when a Matter controller successfully commissions the device.
  """
  @callback handle_commissioning_complete(fabric_index :: non_neg_integer()) :: :ok

  @doc """
  Called when a network (WiFi) is added during commissioning.
  """
  @callback handle_network_added(ssid :: binary(), credentials :: binary()) :: :ok

  @optional_callbacks [
    handle_commissioning_complete: 1,
    handle_network_added: 2
  ]
end
