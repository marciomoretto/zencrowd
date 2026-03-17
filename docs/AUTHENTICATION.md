# Sistema de Autenticação - ZenCrowd

## Visão Geral

Sistema de autenticação baseado em sessões com controle de permissões por papéis (roles). Implementado para a issue #3.

## Arquitetura

### Componentes Principais

1. **Modelo User** (`app/models/user.rb`)
   - Autenticação com `has_secure_password` (bcrypt)
   - 3 roles: admin, annotator, reviewer
   - Validações de email e nome
   - Campo `password_digest` armazenado no banco

2. **SessionsController** (`app/controllers/sessions_controller.rb`)
   - `POST /login` - Autenticação
   - `DELETE /logout` - Encerrar sessão
   - `GET /me` - Informações do usuário logado

3. **ApplicationController** (`app/controllers/application_controller.rb`)
   - Helper methods: `current_user`, `authenticated?`
   - Métodos de autorização: `authenticate_user!`, `authorize_admin!`, etc.

4. **Authorization Concern** (`app/controllers/concerns/authorization.rb`)
   - Lógica de permissões documentada
   - Métodos helper para views: `can_upload_images?`, `can_annotate?`, etc.

## Rotas de Autenticação

```ruby
POST   /login    # Fazer login
DELETE /logout   # Fazer logout
GET    /me       # Obter usuário atual
```

## Fluxo de Login

### Request
```bash
curl -X POST http://localhost:3000/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "admin@example.com",
    "password": "password123"
  }'
```

### Response (200 OK)
```json
{
  "user": {
    "id": 1,
    "email": "admin@example.com",
    "name": "Admin User",
    "role": "admin"
  }
}
```

### Response (401 Unauthorized)
```json
{
  "error": "Email ou senha inválidos"
}
```

## Fluxo de Logout

### Request
```bash
curl -X DELETE http://localhost:3000/logout \
  --cookie "session_cookie"
```

### Response (204 No Content)
Sessão encerrada com sucesso.

## Verificar Usuário Logado

### Request
```bash
curl -X GET http://localhost:3000/me \
  --cookie "session_cookie"
```

### Response (200 OK)
```json
{
  "user": {
    "id": 1,
    "email": "admin@example.com",
    "name": "Admin User",
    "role": "admin"
  }
}
```

### Response (401 Unauthorized)
```json
{
  "error": "Não autenticado"
}
```

## Permissões por Role

### Admin
- ✅ Criar usuários
- ✅ Fazer upload de imagens
- ✅ Visualizar todas as imagens e tarefas
- ✅ Acessar exportação de dataset

### Annotator
- ✅ Visualizar imagens disponíveis
- ✅ Reservar uma imagem
- ✅ Criar anotações (marcar pontos)
- ✅ Submeter anotação
- ❌ Upload de imagens
- ❌ Revisar anotações
- ❌ Exportação de dataset

### Reviewer
- ✅ Visualizar anotações submetidas
- ✅ Revisar anotações
- ✅ Aprovar ou reprovar anotações
- ❌ Reservar imagens
- ❌ Criar anotações
- ❌ Upload de imagens

## Uso em Controllers

### Proteger Endpoint

```ruby
class ImagesController < ApplicationController
  before_action :authenticate_user!  # Requer login
  before_action :authorize_admin!, only: [:create, :upload]  # Apenas admin
  
  def create
    # Apenas usuários admin podem acessar
  end
end
```

### Métodos de Autorização Disponíveis

```ruby
authenticate_user!              # Requer estar logado
authorize_admin!                # Requer role admin
authorize_annotator!            # Requer role annotator
authorize_reviewer!             # Requer role reviewer
authorize_annotator_or_admin!   # Requer annotator OU admin
authorize_role!(:admin, :reviewer)  # Qualquer dos roles especificados
```

### Helper Methods em Views

```ruby
<% if can_upload_images? %>
  <%= link_to "Upload Image", upload_path %>
<% end %>

<% if can_annotate? %>
  <%= link_to "Reserve Task", reserve_path %>
<% end %>

<% if can_review? %>
  <%= link_to "Review Annotations", reviews_path %>
<% end %>
```

## Usuários de Desenvolvimento

Os seguintes usuários estão criados via seeds:

```
admin@example.com       | password123 | admin
annotator@example.com   | password123 | annotator
reviewer@example.com    | password123 | reviewer
```

## Testes

### Executar Testes de Autenticação
```bash
docker-compose run --rm web rspec spec/requests/sessions_spec.rb spec/models/user_spec.rb
```

### Cobertura de Testes
- ✅ Login com credenciais válidas
- ✅ Login com credenciais inválidas
- ✅ Logout
- ✅ Verificação de usuário logado
- ✅ Validação de email
- ✅ Hash seguro de senha
- ✅ Roles (admin, annotator, reviewer)
- ✅ Associações do modelo User

## Migration

```ruby
# db/migrate/20260317004659_add_password_digest_to_users.rb
class AddPasswordDigestToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :password_digest, :string
  end
end
```

## Segurança

- ✅ Senhas armazenadas com bcrypt (hash irreversível)
- ✅ Sessões baseadas em cookie (Rails padrão)
- ✅ CSRF protection habilitado
- ✅ Validações de role em nível de controller
- ✅ Mensagens de erro genéricas (não revela se email existe)

## Próximos Passos

1. Implementar controllers para Images (upload, reserva)
2. Implementar controllers para Annotations (criar, submeter)
3. Implementar controllers para Reviews (aprovar, reprovar)
4. Adicionar autenticação via JWT (opcional, para API mobile)
5. Implementar recuperação de senha
6. Adicionar rate limiting para login

## Critérios de Aceitação ✅

- ✅ Usuários conseguem fazer login com email e senha
- ✅ Sessões autenticadas são mantidas entre requisições
- ✅ Logout encerra corretamente a sessão
- ✅ Usuários não autenticados não conseguem acessar endpoints protegidos
- ✅ Permissões são respeitadas de acordo com o role
- ✅ Tentativas de acesso não autorizado retornam erro apropriado (401/403)
