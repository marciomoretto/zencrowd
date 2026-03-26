# Garante que o locale padrão é pt-BR e força o carregamento das traduções
Rails.application.config.i18n.default_locale = :'pt-BR'
Rails.application.config.i18n.available_locales = [:'pt-BR']
Rails.application.config.i18n.enforce_available_locales = true
