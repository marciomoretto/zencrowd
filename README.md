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

O mosaico e gerado na resolucao maxima das fotos (maior px/m entre elas), sem
teto de pixels; so o limite de 65.500 px por lado do JPEG e aplicado.

### Contagem por recortes automaticos

Ao cortar/contar, o mosaico e dividido automaticamente em recortes de acordo com
sua resolucao (`MosaicTilePlanner`), sem reduzir a imagem. Cada recorte e
processado com margem de sobreposicao e so as cabecas dentro da area propria do
recorte sao contadas, entao ninguem e contado duas vezes. Regioes sem dados
(pretas) sao ignoradas e, se a inferencia estourar a memoria, o recorte e
subdividido em 4 automaticamente.

- `P2PNET_TILE_MAX_PIXELS` (padrao `6000000`): orcamento de pixels por janela de inferencia.
- `P2PNET_TILE_OVERLAP_PX` (padrao `128`): margem de sobreposicao, em pixels, de cada lado.

### Contagem no Cloud Run (opcional)

Por padrao a inferencia roda no proprio servidor (`MOSAIC_COUNT_BACKEND=local`). Com
`MOSAIC_COUNT_BACKEND=cloud_run`, o mosaico e enviado ao Cloud Storage e as janelas sao
processadas em paralelo por um Cloud Run Job (`cloud_run/count_worker`), cujos resultados
o Rails le por polling. Recortes que estouram memoria continuam sendo subdivididos em 4
pelo Rails e reenviados em uma nova rodada. Os dois backends dao a mesma contagem.

Variaveis (valores padrao em `config/deploy.yml`):

- `MOSAIC_COUNT_BACKEND`: `local` ou `cloud_run` (padrao do deploy em `config/deploy.yml`: `cloud_run`; para voltar ao servidor, faca o deploy com `MOSAIC_COUNT_BACKEND=local`).
- `GCP_PROJECT_ID`, `GCP_REGION` (padrao `southamerica-east1`), `GCS_MOSAIC_BUCKET`, `CLOUD_RUN_COUNT_JOB` (padrao `zencrowd-p2pnet-count`).
- `CLOUD_RUN_COUNT_MAX_TASKS` (padrao `10`): maximo de tasks por rodada; o paralelismo real e limitado pelo `--parallelism` do Job.
- `CLOUD_RUN_COUNT_TIMEOUT_SECONDS` (padrao `2400`) e `CLOUD_RUN_COUNT_POLL_SECONDS` (padrao `3`).
- Credenciais: `GOOGLE_CLOUD_KEYFILE_JSON` (conteudo da chave JSON da conta de servico `zencrowd-rails`) ou `GOOGLE_APPLICATION_CREDENTIALS` (caminho do arquivo). Nunca versione a chave; com Kamal, declare-a como secret.

Publicar uma nova versao do worker (apos mudar `cloud_run/count_worker`):

```bash
gcloud builds submit cloud_run/count_worker --project zencrowd-contagem --region southamerica-east1 \
  --tag southamerica-east1-docker.pkg.dev/zencrowd-contagem/zencrowd/count-worker:latest
gcloud run jobs update zencrowd-p2pnet-count --project zencrowd-contagem --region southamerica-east1 \
  --image southamerica-east1-docker.pkg.dev/zencrowd-contagem/zencrowd/count-worker:latest
```

O Job foi criado com 4 vCPU, 16 GiB, `--parallelism 4`, `--max-retries 1` e timeout de 1h por task;
ajuste com `gcloud run jobs update` conforme a cota de CPU da regiao.

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
