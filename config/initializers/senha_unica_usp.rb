SenhaUnicaUSP.configure do |config|
  config.credentials_resolver = lambda do |_context|
    {
      consumer_key: AppSetting.oauth_consumer_key.presence,
      consumer_secret: AppSetting.oauth_consumer_secret.presence,
      callback_id: AppSetting.oauth_callback_id.presence
    }
  end

  # Fallback para variaveis de ambiente quando nao houver segredo no banco.
  config.consumer_key = ENV['ICB_OAUTH']
  config.consumer_secret = ENV['SECRET_OAUTH']
  config.callback_id = ENV['CALLBACK_ID']
end
