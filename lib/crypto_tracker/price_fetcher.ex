defmodule CryptoTracker.PriceFetcher do
  use WebSockex
  require Logger

  def start_link(_) do
    WebSockex.start_link(
      "wss://stream.binance.com:9443/ws/btcusdt@ticker",
      __MODULE__,
      nil,
      name: __MODULE__
    )
  end

  def handle_frame({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, data} ->
        price_data = %{
          price: parse_float(data["c"]),
          high_24h: parse_float(data["h"]),
          low_24h: parse_float(data["l"]),
          volume_24h: parse_float(data["v"])
        }

        Logger.info("Price data: #{inspect(price_data)}")
        {:ok, state}

      {:error, error} ->
        Logger.error("Failed to parse: #{inspect(error)}")
        {:ok, state}
    end
  end

  defp parse_float(str) when is_binary(str) do
    {float, _} = Float.parse(str)
    float
  end

  defp parse_float(_), do: 0.0
end

