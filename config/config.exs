import Config

config :crypto_tracker, :telegram,
  bot_token: System.get_env("TELEGRAM_BOT_TOKEN"),
  chat_id: System.get_env("TELEGRAM_CHAT_ID")

