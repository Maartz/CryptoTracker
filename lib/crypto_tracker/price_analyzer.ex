defmodule CryptoTracker.PriceAnalyzer do
  @moduledoc """
  Analyzes Bitcoin price movements and provides regular price digests.

  This module serves two main purposes:
  1. Detects significant price movements by comparing real-time data with SMAs
  2. Generates minute-by-minute digests of current market conditions

  The analyzer runs as a GenServer process that:
  - Analyzes price movements every second for deviation alerts
  - Provides comprehensive price digests every minute

  ## Alert Conditions
  Alerts are generated when:
  * Price deviates from SMA by more than the configured percentage (default 2%)
  * New price extremes (24h highs/lows) are reached

  ## Digest Information
  Every minute, a digest is sent containing:
  * Current BTC price
  * 24-hour high and low
  * 24-hour trading volume
  * 5-minute Simple Moving Average
  """
  use GenServer
  require Logger

  # 2% deviation from SMA triggers alert
  @price_deviation_threshold 0.02
  # Check price movements every second
  @analysis_interval 1_000
  # Send digest every minute
  @digest_interval 60_000
  # 5 minutes between similar alerts
  @alert_cooldown 300

  # Client API

  @doc """
  Starts the PriceAnalyzer process.
  """
  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  # Server Callbacks

  @doc """
  Initializes the analyzer state and starts both analysis and digest cycles.
  """
  def init(_) do
    schedule_analysis()
    schedule_digest()
    {:ok, %{last_alert: nil}}
  end

  @doc false
  def handle_info(:analyze, state) do
    new_state = analyze_price_movement(state)
    schedule_analysis()
    {:noreply, new_state}
  end

  @doc false
  def handle_info(:digest, state) do
    send_price_digest()
    schedule_digest()
    {:noreply, state}
  end

  defp analyze_price_movement(state) do
    with {:ok, latest_price_data} <- get_latest_price(),
         {:ok, sma} <- CryptoTracker.MovingAverage.get_current_sma() do
      deviation = calculate_deviation(latest_price_data.price, sma)

      state
      |> check_deviation(deviation, latest_price_data.price, sma)
      |> check_24h_extremes(latest_price_data)
    else
      {:error, :no_recent_data} ->
        Logger.warning("No recent price data available for analysis")
        state

      {:error, reason} ->
        Logger.error("Failed to analyze price movement: #{inspect(reason)}")
        state
    end
  end

  defp get_latest_price do
    case CryptoTracker.TimeSeriesStore.get_last_n_minutes(1) do
      [{_timestamp, price_data} | _] -> {:ok, price_data}
      [] -> {:error, :no_recent_data}
    end
  end

  defp calculate_deviation(current_price, sma) do
    (current_price - sma) / sma
  end

  defp check_deviation(state, deviation, price, sma)
       when abs(deviation) >= @price_deviation_threshold do
    direction = if deviation > 0, do: "above", else: "below"
    percent = deviation * 100

    alert = """
    Bitcoin price ($#{format_price(price)}) is #{direction} \
    SMA ($#{format_price(sma)}) by #{format_price(abs(percent))}%
    """

    if not recent_alert?(state, alert) do
      broadcast_alert(alert)
      %{state | last_alert: {System.system_time(:second), alert}}
    else
      state
    end
  end

  defp check_deviation(state, _deviation, _price, _sma), do: state

  defp check_24h_extremes(state, %{price: price, high_24h: high, low_24h: low}) do
    cond do
      price >= high ->
        broadcast_alert("New 24H HIGH: Bitcoin reached $#{format_price(price)}")

      price <= low ->
        broadcast_alert("New 24H LOW: Bitcoin reached $#{format_price(price)}")

      true ->
        :ok
    end

    state
  end

  defp send_price_digest do
    with {:ok, price_data} <- get_latest_price(),
         {:ok, sma} <- CryptoTracker.MovingAverage.get_current_sma() do
      content = """
      Current Price: $#{format_price(price_data.price)}
      24h High: $#{format_price(price_data.high_24h)}
      24h Low: $#{format_price(price_data.low_24h)}
      24h Volume: #{format_price(price_data.volume_24h)} BTC
      5min SMA: $#{format_price(sma)}
      """

      Task.start(fn ->
        case CryptoTracker.Notifications.Telegram.send_message(:digest, content) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.error("Failed to send digest: #{inspect(reason)}")
        end
      end)
    else
      error ->
        Logger.error("Failed to generate price digest: #{inspect(error)}")
    end
  end

  defp recent_alert?(%{last_alert: nil}, _alert), do: false

  defp recent_alert?(%{last_alert: {timestamp, last_alert}}, alert) do
    alert == last_alert and
      System.system_time(:second) - timestamp < @alert_cooldown
  end

  defp broadcast_alert(alert) do
    Logger.warning(alert)

    Task.start(fn ->
      case CryptoTracker.Notifications.Telegram.send_message(:alert, alert) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.error("Failed to send alert: #{inspect(reason)}")
      end
    end)
  end

  defp format_price(number) when is_float(number) do
    :erlang.float_to_binary(number, decimals: 2)
  end

  defp schedule_analysis do
    Process.send_after(self(), :analyze, @analysis_interval)
  end

  defp schedule_digest do
    Process.send_after(self(), :digest, @digest_interval)
  end
end

