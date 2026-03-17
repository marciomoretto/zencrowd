# Resumo do Setup - ZenCrowd

## ✅ O que foi configurado

### 1. Docker e Docker Compose
- **Dockerfile**: Ruby 3.2.10 com PostgreSQL e Node.js
- **docker-compose.yml**: 
  - Web (Rails app)
  - PostgreSQL 15
  - Redis 7

### 2. Ruby on Rails
- Rails 7.1.6
- PostgreSQL configurado
- Estrutura básica criada

### 3. Suite de Testes com RSpec
- **Gems instaladas**:
  - rspec-rails 6.1
  - factory_bot_rails 6.4
  - faker 3.2
  - shoulda-matchers 6.0
  - capybara 3.39
  - selenium-webdriver 4.15

- **Estrutura de diretórios**:
  ```
  spec/
  ├── factories/       # FactoryBot factories
  ├── features/        # Feature/System specs
  ├── models/          # Model specs
  ├── requests/        # Request specs
  ├── controllers/     # Controller specs
  └── support/         # Configurações
      ├── factory_bot.rb
      ├── shoulda_matchers.rb
      └── capybara.rb
  ```

- **Configurações**:
  - RSpec com formato documentation
  - Capybara configurado para testes com e sem JavaScript
  - FactoryBot integrado
  - Shoulda Matchers para validações Rails

## 🚀 Comandos Úteis

### Docker
```bash
# Iniciar serviços
docker-compose up -d

# Parar serviços
docker-compose down

# Ver logs
docker-compose logs -f web
```

### Rails
```bash
# Console
docker-compose run --rm web rails console

# Migrations
docker-compose run --rm web rails db:migrate

# Seeds
docker-compose run --rm web rails db:seed
```

### Testes
```bash
# Todos os testes
docker-compose run --rm web rspec

# Testes específicos
docker-compose run --rm web rspec spec/models
docker-compose run --rm web rspec spec/features

# Com documentação
docker-compose run --rm web rspec --format documentation
```

## 📁 Arquivos Criados

- `Dockerfile`
- `docker-compose.yml`
- `Gemfile` (atualizado)
- `.dockerignore`
- `spec/README.md` - Documentação dos testes
- `spec/support/factory_bot.rb`
- `spec/support/shoulda_matchers.rb`
- `spec/support/capybara.rb`
- `.rspec` (configurado)

## ⚙️ Configurações

### Banco de Dados
- **Development**: zencrowd_development
- **Test**: zencrowd_test
- **Usuário**: postgres / postgres

### Portas Expostas
- Rails: 3000
- PostgreSQL: 5432
- Redis: 6379

## 📝 Próximos Passos

1. Criar models iniciais (User, Image, Annotation, etc.)
2. Escrever testes para os models
3. Criar controllers e views
4. Implementar autenticação
5. Desenvolver interface de anotação

## 🔧 Nota sobre Ruby 3.2.10

Há um bug conhecido de compatibilidade com a gem CGI no Ruby 3.2.10. 
Se encontrar erros relacionados a `@@accept_charset`, considere:
- Usar Ruby 3.2.0 (alterar no Gemfile e Dockerfile)
- Ou aguardar fix nas gems atualizadas

