# Máquina de Estados - Fluxo de Imagens

Este documento descreve a máquina de estados que controla o ciclo de vida de cada imagem no sistema ZenCrowd.

## Estados Disponíveis

| Estado | Descrição |
|--------|-----------|
| `available` | Imagem disponível para reserva por anotadores |
| `reserved` | Imagem reservada por um anotador específico |
| `submitted` | Anotação enviada pelo anotador, aguardando revisão |
| `in_review` | Anotação em processo de revisão |
| `approved` | Anotação aprovada pelo revisor |
| `rejected` | Anotação rejeitada (retorna para reserved) |
| `paid` | Tarefa marcada como paga pelo administrador |

## Diagrama de Transições

```
available ──────┐
    ↑          │
    │          ↓
    │      reserved ←────┐
    │          │         │
    │          ↓         │
    │      submitted     │
    │          │         │
    │          ↓         │
    │      in_review     │
    │        ↙  ↘        │
    │       ↙    ↘       │
    │  approved  rejected┘
    │      │
    │      ↓
    │    paid
    │
    └──(expiração)
```

## Transições Permitidas

### 1. available → reserved
**Ação**: Reservar imagem  
**Endpoint**: `POST /images/:id/reserve`  
**Permissão**: Annotator  
**Regras**:
- Imagem deve estar em status `available`
- Usuário deve ter role `annotator`
- Usuário não pode ter outra imagem reservada

```bash
curl -X POST http://localhost:3000/images/1/reserve -b cookies.txt
```

### 2. reserved → submitted
**Ação**: Submeter anotação  
**Endpoint**: `POST /images/:id/submit`  
**Permissão**: Annotator (que reservou)  
**Regras**:
- Imagem deve estar em status `reserved`
- Apenas o usuário que reservou pode submeter

```bash
curl -X POST http://localhost:3000/images/1/submit -b cookies.txt
```

### 3. submitted → in_review
**Ação**: Iniciar revisão  
**Endpoint**: `POST /images/:id/start_review`  
**Permissão**: Reviewer  
**Regras**:
- Imagem deve estar em status `submitted`
- Usuário deve ter role `reviewer`

```bash
curl -X POST http://localhost:3000/images/1/start_review -b cookies.txt
```

### 4. in_review → approved
**Ação**: Aprovar anotação  
**Endpoint**: `POST /images/:id/approve`  
**Permissão**: Reviewer  
**Regras**:
- Imagem deve estar em status `in_review`
- Usuário deve ter role `reviewer`

```bash
curl -X POST http://localhost:3000/images/1/approve -b cookies.txt
```

### 5. in_review → rejected → reserved
**Ação**: Rejeitar anotação  
**Endpoint**: `POST /images/:id/reject`  
**Permissão**: Reviewer  
**Regras**:
- Imagem deve estar em status `in_review`
- Usuário deve ter role `reviewer`
- Retorna para `reserved` com mesmo usuário
- `reserved_at` é atualizado

```bash
curl -X POST http://localhost:3000/images/1/reject -b cookies.txt
```

### 6. approved → paid
**Ação**: Marcar como pago  
**Endpoint**: `POST /images/:id/mark_paid`  
**Permissão**: Admin  
**Regras**:
- Imagem deve estar em status `approved`
- Usuário deve ter role `admin`

```bash
curl -X POST http://localhost:3000/images/1/mark_paid -b cookies.txt
```

### 7. reserved → available (Expiração)
**Ação**: Expirar reserva  
**Endpoint**: `POST /images/:id/expire_reservation` (manual)  
**Permissão**: Admin  
**Regras**:
- Imagem deve estar em status `reserved`
- Pode ser executado automaticamente via rake task

```bash
# Manual (admin)
curl -X POST http://localhost:3000/images/1/expire_reservation -b cookies.txt

# Automático (rake task)
docker-compose run --rm web bundle exec rake images:expire_reservations
```

## Regras de Negócio

### Reserva de Imagens
- **Uma imagem por vez**: Cada anotador pode ter no máximo uma imagem reservada
- **Exclusividade**: Uma imagem reservada não pode ser reservada por outro usuário
- **Tempo limite**: Reservas expiram após 48 horas (configurável)

### Submissão
- Apenas o anotador que reservou pode submeter a anotação
- Após submissão, a imagem não pode mais ser editada pelo anotador

### Revisão
- Qualquer revisor pode iniciar a revisão de uma anotação submetida
- Revisor pode aprovar ou rejeitar

### Rejeição
- Quando rejeitada, a tarefa retorna para o mesmo anotador
- O anotador deve corrigir e resubmeter
- Timestamp `reserved_at` é atualizado

### Expiração
- Reservas com mais de 48 horas expiram automaticamente
- Imagem volta para `available`
- Campos `reserver` e `reserved_at` são limpos

## Configuração

### Tempo de Expiração
Defina o tempo de expiração no modelo `Image`:

```ruby
# app/models/image.rb
RESERVATION_EXPIRATION_HOURS = 48
```

### Automação de Expiração

Para executar a expiração automaticamente, configure um cron job:

```bash
# Adicionar ao crontab
0 */6 * * * cd /path/to/app && docker-compose run --rm web bundle exec rake images:expire_reservations
```

Ou use um scheduler como Whenever gem:

```ruby
# config/schedule.rb
every 6.hours do
  rake "images:expire_reservations"
end
```

## Respostas da API

### Sucesso
```json
{
  "id": 1,
  "original_filename": "image.jpg",
  "storage_path": "storage/uploads/images/...",
  "status": "reserved",
  "task_value": 10.0,
  "uploader": { "id": 1, "name": "Admin", "email": "admin@example.com" },
  "reserver": { "id": 2, "name": "Annotator", "email": "ann@example.com" },
  "reserved_at": "2026-03-16T12:00:00.000Z",
  "created_at": "2026-03-16T10:00:00.000Z",
  "updated_at": "2026-03-16T12:00:00.000Z"
}
```

### Erro de Transição Inválida
```json
{
  "error": "Image is not available"
}
```

### Erro de Permissão
```json
{
  "error": "Permissão negada"
}
```

### Erro de Autenticação
```json
{
  "error": "Autenticação necessária"
}
```

## Fluxo Completo de Exemplo

### 1. Admin faz upload
```bash
curl -X POST http://localhost:3000/login \
  -d '{"email":"admin@example.com","password":"pass"}' \
  -c cookies-admin.txt

curl -X POST http://localhost:3000/images \
  -F "file=@image.jpg" \
  -F "task_value=15.00" \
  -b cookies-admin.txt
```

### 2. Annotator reserva
```bash
curl -X POST http://localhost:3000/login \
  -d '{"email":"annotator@example.com","password":"pass"}' \
  -c cookies-annotator.txt

curl -X POST http://localhost:3000/images/1/reserve \
  -b cookies-annotator.txt
```

### 3. Annotator submete
```bash
curl -X POST http://localhost:3000/images/1/submit \
  -b cookies-annotator.txt
```

### 4. Reviewer revisa e aprova
```bash
curl -X POST http://localhost:3000/login \
  -d '{"email":"reviewer@example.com","password":"pass"}' \
  -c cookies-reviewer.txt

curl -X POST http://localhost:3000/images/1/start_review \
  -b cookies-reviewer.txt

curl -X POST http://localhost:3000/images/1/approve \
  -b cookies-reviewer.txt
```

### 5. Admin marca como pago
```bash
curl -X POST http://localhost:3000/images/1/mark_paid \
  -b cookies-admin.txt
```

## Testes

Execute os testes da máquina de estados:

```bash
# Testes do modelo
docker-compose run --rm web bundle exec rspec spec/models/image_state_machine_spec.rb

# Testes dos endpoints
docker-compose run --rm web bundle exec rspec spec/requests/image_transitions_spec.rb

# Todos os testes
docker-compose run --rm web bundle exec rspec
```

## Métricas e Monitoramento

Para monitorar o fluxo de imagens:

```ruby
# Console Rails
Image.group(:status).count
# => {"available"=>10, "reserved"=>5, "submitted"=>3, "in_review"=>2, "approved"=>8, "paid"=>12}

# Reservas expiradas
Image.expired_reservations.count

# Imagens por anotador
Image.where(status: :reserved).group(:reserver_id).count
```

## Troubleshooting

### Usuário não consegue reservar imagem
- Verificar se já tem uma imagem reservada
- Verificar se a imagem está disponível
- Verificar se o usuário tem role `annotator`

### Reserva não expira automaticamente
- Verificar se o cron job está configurado
- Executar manualmente: `rake images:expire_reservations`
- Verificar logs

### Erro de "double render"
- Controladores já tratam autorização
- Não adicionar renders duplicados
