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
- Sidekiq 7 (jobs em background)
- RSpec + Capybara + FactoryBot
- Docker + Docker Compose
- Bootstrap 5

Dependencias de destaque:

- `mosaico_dji.py` (geracao de mosaicos DJI)
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
- Python 3 com as dependencias de `requirements-mosaic.txt`
- ExifTool (`libimage-exiftool-perl` no Ubuntu/Debian)

## Geracao de mosaicos

O ZenCrowd usa a implementacao DJI mantida em `lib/mosaico/mosaico_dji.py`.
O Docker instala as dependencias Python de mosaico e de contagem no ambiente
isolado usado pelos jobs. Em execucoes locais, `MOSAIC_PYTHON_BIN` pode apontar
para o Python que tem `requirements-mosaic.txt` instalado; se nao estiver
definido, o app reutiliza `P2PNET_PYTHON_BIN` ou `python3`. A contagem P2PNet
continua sendo executada pelo fluxo de corte/contagem existente do ZenCrowd.

## Subindo o Projeto com Docker

1. Construir imagem:

```bash
docker compose build
```

2. Subir servicos:

```bash
docker compose up -d

# opcional: subir apenas web+worker+infra explicitamente
docker compose up -d web sidekiq db redis
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
docker compose logs -f sidekiq
```

Console Rails:

```bash
docker compose run --rm web bundle exec rails console
```

Migracoes:

```bash
docker compose run --rm web bundle exec rails db:migrate

## Background Jobs (Sidekiq)

Os fluxos longos (corte/contagem/mosaico e processamento de metadados) rodam em background.

Para funcionar corretamente em desenvolvimento:

1. mantenha o Redis ativo
2. mantenha o worker `sidekiq` ativo
3. use o app normalmente no `web`

Se o worker estiver parado, os jobs ficam enfileirados e nao avancam.
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
