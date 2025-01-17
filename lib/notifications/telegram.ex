defmodule CryptoTracker.Notifications.Telegram do
  @moduledoc """
  Handles sending notifications to Telegram for the CryptoTracker application.

  This module provides a robust interface for sending formatted messages to a Telegram
  chat, supporting both real-time price alerts and scheduled price digests. It uses
  the Telegram Bot API to deliver messages with proper formatting and error handling.

  ## Configuration

  Requires the following environment variables to be set:
  * `TELEGRAM_BOT_TOKEN` - The bot token obtained from BotFather
  * `TELEGRAM_CHAT_ID` - The chat ID where messages will be sent

  These should be configured in your .env file:
      TELEGRAM_BOT_TOKEN=your_bot_token_here
      TELEGRAM_CHAT_ID=your_chat_id_here

  ## Message Types

  The module supports two types of formatted messages:
  * `:alert` - For urgent price movement notifications (🚨)
  * `:digest` - For regular price updates (🔔)

  ## Examples

      # Send a simple message
      CryptoTracker.Notifications.Telegram.send_message("Hello from CryptoTracker!")

      # Send a formatted digest
      CryptoTracker.Notifications.Telegram.send_message(:digest, "BTC Price: $50,000")

      # Send a formatted alert
      CryptoTracker.Notifications.Telegram.send_message(:alert, "Price up by 5%!")
  """

  use Tesla
  require Logger

  @base_url "https://api.telegram.org"

  # Get configuration from application config
  defp bot_token, do: Application.get_env(:crypto_tracker, :telegram)[:bot_token]
  defp chat_id, do: Application.get_env(:crypto_tracker, :telegram)[:chat_id]

  plug(Tesla.Middleware.BaseUrl, "#{@base_url}/bot#{bot_token()}")
  plug(Tesla.Middleware.JSON)

  @doc """
  Sends a formatted message to Telegram based on the specified type.

  ## Parameters
    * `type` - Either `:alert` or `:digest`, determines the message formatting
    * `content` - The message content to be sent

  ## Returns
    * `:ok` - Message was sent successfully
    * `{:error, reason}` - Failed to send message

  ## Examples
      iex> send_message(:digest, "Current BTC Price: $50,000")
      :ok

      iex> send_message(:alert, "Significant price movement detected!")
      :ok
  """
  def send_message(type, content) when is_atom(type) and is_binary(content) do
    formatted_message = format_message(type, content)
    do_send_message(formatted_message)
  end

  @doc """
  Sends a plain message to Telegram without special formatting.

  ## Parameters
    * `content` - The message content to be sent

  ## Returns
    * `:ok` - Message was sent successfully
    * `{:error, reason}` - Failed to send message

  ## Example
      iex> send_message("Simple status update")
      :ok
  """
  def send_message(content) when is_binary(content) do
    do_send_message(content)
  end

  defp do_send_message(message) do
    body = %{
      "chat_id" => chat_id(),
      "text" => message,
      "parse_mode" => "HTML"
    }

    Logger.debug("Sending Telegram message: #{inspect(body, pretty: true)}")

    case post("/sendMessage", body) do
      {:ok, %Tesla.Env{status: 200, body: %{"ok" => true}}} ->
        Logger.info("Successfully sent message to Telegram")
        :ok

      {:ok, %Tesla.Env{status: status, body: body}} ->
        Logger.error("Telegram API error - Status: #{status}, Body: #{inspect(body)}")
        {:error, "Telegram API error (status #{status}): #{inspect(body)}"}

      {:error, reason} ->
        Logger.error("Request failed: #{inspect(reason)}")
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  defp format_message(:alert, content) do
    """
    🚨 <b>CRYPTO ALERT</b> 🚨
    #{content}
    <i>#{format_timestamp()}</i>
    """
  end

  defp format_message(:digest, content) do
    """
    🔔 <b>Minute digest</b> 🔔
    #{content}
    <i>#{format_timestamp()}</i>
    """
  end

  defp format_timestamp do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_string()
  end
end

