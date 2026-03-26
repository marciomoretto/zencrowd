# ZenCrowd

Plataforma web para anotacao e revisao de tiles de imagem em fluxo colaborativo (crowdsourcing), com papeis de administrador, anotador e revisor.

## Visao Geral

O ZenCrowd organiza o trabalho em tarefas por tile, com ciclo de vida completo:

1. upload e gerenciamento de tiles
2. reserva por anotadores
3. submissao de pontos
4. revisao/aprovacao
5. controle de pagamentos

Tambem inclui:

- dashboard por papel
- configuracoes operacionais (valor por cabeca, expiracao de tarefa, limite de orcamento, pagamento minimo)
- exportacao de dataset
- suporte a paginacao nas telas administrativas e operacionais

## Stack Tecnica

- Ruby 3.2.10
- Rails 7.1.6
- PostgreSQL 15
- Redis 7
- RSpec + Capybara + FactoryBot
- Docker + Docker Compose
- Bootstrap 5

Dependencias de destaque:

- `crowd_counting_p2pnet` (contagem)
- `zen_plot` (editor de pontos)
- `kaminari` (paginacao)
- `ruby-vips` (processamento de imagem)

## Requisitos

Opcao recomendada (Docker):

- Docker
- Docker Compose

Opcao local (sem Docker):

- Ruby 3.2.10
- PostgreSQL 15
- Redis 7
- libvips

## Subindo o Projeto com Docker

1. Construir imagem:

```bash
docker compose build
```

2. Subir servicos:

```bash
docker compose up -d
```

3. Criar e migrar banco:

```bash
docker compose run --rm web bundle exec rails db:create db:migrate
```

4. Popular dados iniciais:

```bash
docker compose run --rm web bundle exec rails db:seed
```

5. Acessar aplicacao:

- http://localhost:3000

## Comandos Uteis

Subir/parar ambiente:

```bash
docker compose up -d
docker compose down
```

Logs:

```bash
docker compose logs -f web
```

Console Rails:

```bash
docker compose run --rm web bundle exec rails console
```

Migracoes:

```bash
docker compose run --rm web bundle exec rails db:migrate
```

## Testes

Suite completa:

```bash
docker compose run --rm -e RAILS_ENV=test web bundle exec rspec
```

Specs especificos:

```bash
docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/models
docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/features
docker compose run --rm -e RAILS_ENV=test web bundle exec rspec spec/requests
```

## Usuarios de Desenvolvimento (Seeds)

As seeds criam usuarios de exemplo com senha:

- `password123`

Exemplos de contas normalmente criadas:

- admin: `admin@admin.com`
- admin: `admin@example.com`
- reviewer: `reviewer@example.com`
- annotator: `annotator@example.com`
- annotator: `annotator1@example.com`

Observacao: o arquivo de seed contem mais contas de apoio para cenarios de teste visual e fluxo de pagamentos.

## Estrutura Principal

```text
app/
	controllers/
	models/
	views/
spec/
	features/
	models/
	requests/
config/
db/
```

## Troubleshooting

### Erro com vips

Se aparecer erro relacionado a `vips`, valide a dependencia:

```bash
docker compose run --rm web bundle exec ruby -e "require 'vips'; puts Vips::VERSION"
```

Sem Docker (Linux):

```bash
sudo apt-get update
sudo apt-get install -y libvips libvips-tools
```

### Permissao de arquivos no container

O servico `web` usa `UID/GID` do host. Se houver problema de permissao, exporte:

```bash
export UID=$(id -u)
export GID=$(id -g)
```

### Erro de pid ao subir Rails

O comando do container ja remove `tmp/pids/server.pid` automaticamente. Se ainda ocorrer, rode:

```bash
docker compose down
docker compose up -d
```

## Licenca

Consulte o arquivo LICENSE para detalhes.
