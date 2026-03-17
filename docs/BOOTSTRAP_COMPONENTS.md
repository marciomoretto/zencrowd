# Guia de Componentes Bootstrap - ZenCrowd

Este documento descreve os componentes reutilizáveis disponíveis no projeto.

## Layout Base

O layout base está em `app/views/layouts/application.html.erb` e inclui:

- **Bootstrap 5.3.0** via CDN
- **Bootstrap Icons** para ícones
- Navbar responsiva
- Flash messages
- Footer
- Sistema de content_for para customização

### Customizando o Layout

```erb
<% content_for :title, "Minha Página" %>

<% content_for :hero do %>
  <div class="bg-primary text-white py-5">
    <!-- Conteúdo do hero -->
  </div>
<% end %>

<% content_for :container_class, "container-fluid" %>

<!-- Conteúdo da página -->
```

## Componentes Reutilizáveis

### 1. Navbar (`_navbar.html.erb`)

Navbar responsiva com:
- Logo/Brand
- Menu de navegação baseado em roles
- Dropdown de usuário
- Links de login/cadastro

A navbar adapta automaticamente os links baseado no papel do usuário (admin, annotator, reviewer).

### 2. Flash Messages (`_flash_messages.html.erb`)

Exibe mensagens flash automaticamente com Bootstrap alerts:

```ruby
# No controller
flash[:notice] = "Operação realizada com sucesso!"
flash[:alert] = "Atenção: verifique os dados"
flash[:error] = "Erro ao processar o pedido"
```

### 3. Footer (`_footer.html.erb`)

Footer padrão com:
- Informações do projeto
- Links úteis
- Copyright dinâmico

### 4. Card (`_card.html.erb`)

Card Bootstrap reutilizável:

```erb
<%= render 'shared/card', 
    title: 'Título do Card', 
    icon: 'bi-star',
    footer: 'Rodapé opcional' do %>
  Conteúdo do card aqui
<% end %>
```

Ou com parâmetro body:

```erb
<%= render 'shared/card',
    title: 'Título',
    body: 'Conteúdo simples' %>
```

### 5. Empty State (`_empty_state.html.erb`)

Estado vazio customizável:

```erb
<%= render 'shared/empty_state',
    icon: 'bi-inbox',
    title: 'Nenhuma imagem encontrada',
    message: 'Não há imagens disponíveis no momento.',
    action_text: 'Upload de Imagem',
    action_path: new_image_path %>
```

### 6. Loading Spinner (`_loading_spinner.html.erb`)

Spinner de carregamento:

```erb
<%= render 'shared/loading_spinner', 
    text: 'Processando...', 
    size: 'sm',
    show_text: true %>
```

Tamanhos: `sm` (pequeno), `lg` (grande), ou vazio para padrão.

### 7. Modal de Confirmação (`_confirm_modal.html.erb`)

Modal de confirmação customizável:

```erb
<%= render 'shared/confirm_modal',
    id: 'deleteModal',
    title: 'Confirmar Exclusão',
    message: 'Tem certeza que deseja excluir esta imagem?',
    confirm_text: 'Excluir',
    cancel_text: 'Cancelar',
    confirm_class: 'btn-danger' do %>
  
  <%= button_to item_path(@item), 
      method: :delete, 
      class: "btn #{confirm_class}",
      data: { bs_dismiss: 'modal' } do %>
    <%= confirm_text %>
  <% end %>
<% end %>

<!-- Botão que abre o modal -->
<button type="button" class="btn btn-danger" data-bs-toggle="modal" data-bs-target="#deleteModal">
  Excluir
</button>
```

## Bootstrap Icons

O projeto usa Bootstrap Icons. Exemplos:

```erb
<i class="bi bi-images"></i>
<i class="bi bi-pencil-square"></i>
<i class="bi bi-check-circle"></i>
<i class="bi bi-person-circle"></i>
<i class="bi bi-trash"></i>
```

Lista completa: https://icons.getbootstrap.com/

## Classes CSS Customizadas

### Button Loading State

```html
<button class="btn btn-primary btn-loading">
  Processando...
</button>
```

### Status Badges

```html
<span class="badge status-badge bg-success">Aprovado</span>
<span class="badge status-badge bg-warning">Em Revisão</span>
<span class="badge status-badge bg-danger">Rejeitado</span>
```

### Image Preview

```html
<img src="image.jpg" class="image-preview" alt="Preview">
```

## Layouts de Grid Comuns

### Duas Colunas

```erb
<div class="row">
  <div class="col-md-6">
    <!-- Coluna esquerda -->
  </div>
  <div class="col-md-6">
    <!-- Coluna direita -->
  </div>
</div>
```

### Três Colunas (Cards)

```erb
<div class="row g-4">
  <div class="col-md-4">
    <%= render 'shared/card', title: 'Card 1' do %>
      Conteúdo 1
    <% end %>
  </div>
  <div class="col-md-4">
    <%= render 'shared/card', title: 'Card 2' do %>
      Conteúdo 2
    <% end %>
  </div>
  <div class="col-md-4">
    <%= render 'shared/card', title: 'Card 3' do %>
      Conteúdo 3
    <% end %>
  </div>
</div>
```

### Sidebar + Conteúdo

```erb
<div class="row">
  <div class="col-md-3">
    <!-- Sidebar -->
  </div>
  <div class="col-md-9">
    <!-- Conteúdo principal -->
  </div>
</div>
```

## Formulários

### Formulário Básico

```erb
<%= form_with model: @item, class: "needs-validation", novalidate: true do |f| %>
  <div class="mb-3">
    <%= f.label :name, class: "form-label" %>
    <%= f.text_field :name, class: "form-control", required: true %>
    <div class="invalid-feedback">
      Campo obrigatório
    </div>
  </div>
  
  <div class="mb-3">
    <%= f.label :description, class: "form-label" %>
    <%= f.text_area :description, class: "form-control", rows: 3 %>
  </div>
  
  <%= f.submit "Salvar", class: "btn btn-primary" %>
<% end %>
```

### Upload de Arquivo

```erb
<div class="mb-3">
  <%= f.label :file, "Arquivo", class: "form-label" %>
  <%= f.file_field :file, class: "form-control", accept: "image/*" %>
</div>
```

## Tabelas Responsivas

```erb
<div class="table-responsive">
  <table class="table table-striped table-hover">
    <thead>
      <tr>
        <th>ID</th>
        <th>Nome</th>
        <th>Status</th>
        <th>Ações</th>
      </tr>
    </thead>
    <tbody>
      <% @items.each do |item| %>
        <tr>
          <td><%= item.id %></td>
          <td><%= item.name %></td>
          <td><span class="badge bg-success"><%= item.status %></span></td>
          <td>
            <%= link_to item_path(item), class: "btn btn-sm btn-primary" do %>
              <i class="bi bi-eye"></i>
            <% end %>
          </td>
        </tr>
      <% end %>
    </tbody>
  </table>
</div>
```

## Alerts e Notificações

### Alert Básico

```erb
<div class="alert alert-info alert-dismissible fade show" role="alert">
  <i class="bi bi-info-circle"></i> Informação importante
  <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
</div>
```

### Toast Notifications (JavaScript)

```html
<div class="toast-container position-fixed bottom-0 end-0 p-3">
  <div id="liveToast" class="toast" role="alert">
    <div class="toast-header">
      <strong class="me-auto">Notificação</strong>
      <button type="button" class="btn-close" data-bs-dismiss="toast"></button>
    </div>
    <div class="toast-body">
      Mensagem da notificação
    </div>
  </div>
</div>
```

## Cores do Tema

Bootstrap 5 usa as seguintes cores principais:

- **primary** - Azul (cor principal do ZenCrowd)
- **secondary** - Cinza
- **success** - Verde (aprovado)
- **danger** - Vermelho (erro, rejeitado)
- **warning** - Amarelo (atenção)
- **info** - Azul claro
- **light** - Cinza claro
- **dark** - Preto

## Responsividade

Bootstrap usa breakpoints:

- **xs**: < 576px (extra small)
- **sm**: ≥ 576px (small)
- **md**: ≥ 768px (medium)
- **lg**: ≥ 992px (large)
- **xl**: ≥ 1200px (extra large)
- **xxl**: ≥ 1400px (extra extra large)

Exemplo:
```html
<div class="col-12 col-md-6 col-lg-4">
  <!-- 100% em mobile, 50% em tablet, 33% em desktop -->
</div>
```

## Documentação Completa

- Bootstrap: https://getbootstrap.com/docs/5.3/
- Bootstrap Icons: https://icons.getbootstrap.com/
- Rails Guides: https://guides.rubyonrails.org/
