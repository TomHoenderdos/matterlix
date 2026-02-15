defmodule Matterlix.Handler.Default do
  @moduledoc false
  @behaviour Matterlix.Handler

  require Logger

  @impl true
  def handle_attribute_change(endpoint_id, cluster_id, attribute_id, _type, value) do
    Logger.debug(
      "Matterlix: Unhandled attribute change — " <>
        "endpoint=#{endpoint_id}, cluster=0x#{Integer.to_string(cluster_id, 16)}, " <>
        "attr=0x#{Integer.to_string(attribute_id, 16)}, value=#{inspect(value)}"
    )

    :ok
  end

  @impl true
  def handle_commissioning_complete(_fabric_index), do: :ok

  @impl true
  def handle_network_added(_ssid, _credentials), do: :ok
end
