# API de Upload e Listagem de Imagens

Esta documentação descreve os endpoints para upload e listagem de imagens na plataforma ZenCrowd.

## Permissões

**Apenas usuários com role `admin` podem acessar estes endpoints.**

Usuários com roles `annotator` ou `reviewer` receberão erro 403 (Forbidden).

## Endpoints

### GET /images

Lista todas as imagens cadastradas no sistema.

#### Requisitos
- Usuário autenticado
- Role: `admin`

#### Exemplo de Request
```bash
curl -X GET http://localhost:3000/images \
  -H "Content-Type: application/json" \
  -b cookies.txt
```

#### Resposta de Sucesso (200 OK)
```json
[
  {
    "id": 1,
    "original_filename": "exemplo.jpg",
    "storage_path": "storage/uploads/images/20260316120000_a1b2c3d4e5f6g7h8.jpg",
    "status": "available",
    "task_value": 10.0,
    "uploader": {
      "id": 1,
      "name": "Admin User",
      "email": "admin@example.com"
    },
    "reserver": null,
    "reserved_at": null,
    "created_at": "2026-03-16T12:00:00.000Z",
    "updated_at": "2026-03-16T12:00:00.000Z"
  }
]
```

#### Possíveis Erros
- **401 Unauthorized**: Usuário não autenticado
- **403 Forbidden**: Usuário não possui role admin

---

### POST /images

Faz upload de uma nova imagem para o sistema.

#### Requisitos
- Usuário autenticado
- Role: `admin`

#### Parâmetros
| Parâmetro | Tipo | Obrigatório | Descrição |
|-----------|------|-------------|-----------|
| file | File | Sim | Arquivo de imagem (JPG, JPEG ou PNG) |
| task_value | Decimal | Não | Valor da tarefa de anotação |

#### Validações
- **Formato**: Apenas JPG, JPEG, PNG
- **Tamanho máximo**: 10MB
- **Arquivo**: Obrigatório

#### Exemplo de Request
```bash
curl -X POST http://localhost:3000/images \
  -F "file=@path/to/image.jpg" \
  -F "task_value=15.50" \
  -b cookies.txt
```

#### Resposta de Sucesso (201 Created)
```json
{
  "id": 2,
  "original_filename": "image.jpg",
  "storage_path": "storage/uploads/images/20260316123456_x9y8z7w6v5u4t3s2.jpg",
  "status": "available",
  "task_value": 15.5,
  "uploader": {
    "id": 1,
    "name": "Admin User",
    "email": "admin@example.com"
  },
  "reserver": null,
  "reserved_at": null,
  "created_at": "2026-03-16T12:34:56.000Z",
  "updated_at": "2026-03-16T12:34:56.000Z"
}
```

#### Possíveis Erros

**401 Unauthorized** - Usuário não autenticado
```json
{
  "error": "Autenticação necessária"
}
```

**403 Forbidden** - Usuário não possui role admin
```json
{
  "error": "Permissão negada"
}
```

**422 Unprocessable Entity** - Arquivo não enviado
```json
{
  "error": "Nenhum arquivo foi enviado"
}
```

**422 Unprocessable Entity** - Formato não suportado
```json
{
  "error": "Formato de arquivo não suportado. Use JPG, JPEG ou PNG"
}
```

**422 Unprocessable Entity** - Arquivo muito grande
```json
{
  "error": "Arquivo muito grande. Tamanho máximo: 10MB"
}
```

**422 Unprocessable Entity** - Erros de validação
```json
{
  "errors": [
    "Original filename can't be blank",
    "Storage path can't be blank"
  ]
}
```

## Status das Imagens

As imagens podem ter os seguintes status ao longo do fluxo:

| Status | Descrição |
|--------|-----------|
| `available` | Imagem disponível para reserva (status inicial) |
| `abandoned` | Tarefa abandonada (desistência/expiração), disponível para nova reserva |
| `reserved` | Imagem reservada por um anotador |
| `submitted` | Estado legado (compatibilidade) |
| `in_review` | Em processo de revisão (status após submissão) |
| `approved` | Anotação aprovada |
| `rejected` | Anotação rejeitada |
| `paid` | Tarefa paga ao anotador |

**Nota**: No momento do upload, todas as imagens são criadas com status `available`.

## Armazenamento de Arquivos

Os arquivos enviados são armazenados localmente em:
```
storage/uploads/images/
```

O nome do arquivo é gerado automaticamente usando:
- Timestamp (YYYYMMDDHHmmss)
- Token aleatório (16 caracteres hexadecimais)
- Extensão original do arquivo

**Exemplo**: `20260316123456_a1b2c3d4e5f6g7h8.jpg`

Isso garante que:
- Não haja conflitos de nomes
- Os arquivos sejam organizados cronologicamente
- O sistema seja seguro contra sobrescrita acidental

## Fluxo Completo de Uso

1. **Fazer login como admin**
```bash
curl -X POST http://localhost:3000/login \
  -H "Content-Type: application/json" \
  -d '{"email": "admin@example.com", "password": "senha123"}' \
  -c cookies.txt
```

2. **Fazer upload de uma imagem**
```bash
curl -X POST http://localhost:3000/images \
  -F "file=@imagem.jpg" \
  -F "task_value=20.00" \
  -b cookies.txt
```

3. **Listar todas as imagens**
```bash
curl -X GET http://localhost:3000/images \
  -b cookies.txt
```

4. **Fazer logout**
```bash
curl -X DELETE http://localhost:3000/logout \
  -b cookies.txt
```

## Testes

Para executar os testes desta funcionalidade:

```bash
# Todos os testes de imagens
docker-compose run --rm web bundle exec rspec spec/requests/images_spec.rb

# Todos os testes do projeto
docker-compose run --rm web bundle exec rspec
```

## Cobertura de Testes

A funcionalidade possui **16 testes** cobrindo:

### GET /images
- ✅ Listagem completa de imagens
- ✅ Detalhes das imagens
- ✅ Informações de reserver quando presente
- ✅ Array vazio quando não há imagens
- ✅ Rejeição de acesso para annotator
- ✅ Rejeição de acesso para reviewer
- ✅ Rejeição de acesso para usuários não autenticados

### POST /images
- ✅ Upload bem-sucedido de imagem
- ✅ Criação de registro no banco de dados
- ✅ Aceitação de diferentes formatos (JPG, JPEG, PNG)
- ✅ Upload sem task_value (opcional)
- ✅ Rejeição de upload sem arquivo
- ✅ Rejeição de formatos não suportados
- ✅ Rejeição de acesso para annotator
- ✅ Rejeição de acesso para reviewer
- ✅ Rejeição de acesso para usuários não autenticados

## Próximos Passos

Funcionalidades futuras podem incluir:
- Armazenamento em nuvem (AWS S3, Azure Blob, etc.)
- Miniatura/thumbnail das imagens
- Exclusão de imagens
- Atualização de task_value
- Filtros e paginação na listagem
- Download de imagens
