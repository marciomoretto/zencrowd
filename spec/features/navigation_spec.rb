require 'rails_helper'

RSpec.feature "Navigation", type: :feature do
  scenario "Usuário não autenticado vê apenas login e cadastro" do
    visit root_path
    expect(page).to have_link("Entrar", href: login_path)
    expect(page).to have_link("Cadastrar", href: signup_path)
    expect(page).not_to have_link("Imagens", exact: true)
    expect(page).not_to have_link("Upload de Imagem")
    expect(page).not_to have_link("Exportar Dataset")
    expect(page).not_to have_link("Tarefas Disponíveis")
    expect(page).not_to have_link("Tarefa Atual")
    expect(page).not_to have_link("Minhas Tarefas")
    expect(page).not_to have_link("Tarefas em Revisão")
  end

  scenario "Annotator vê navegação de annotator" do
    user = User.create!(name: "Ana", email: "ana@ex.com", password: "senha123", password_confirmation: "senha123", role: :annotator)
    visit login_path
    fill_in "E-mail", with: user.email
    fill_in "Senha", with: "senha123"
    click_button "Entrar"
    expect(page).to have_link("Tarefas Disponíveis", href: available_tiles_path)
    expect(page).to have_link("Tarefa Atual", href: my_task_path)
    expect(page).to have_link("Minhas Tarefas", href: completed_tasks_path)
    expect(page).not_to have_link("Imagens", exact: true)
    expect(page).not_to have_link("Upload de Tile")
    expect(page).not_to have_link("Upload de Imagem")
    expect(page).not_to have_link("Exportar Dataset")
    expect(page).not_to have_link("Tarefas em Revisão")
  end

  scenario "Reviewer vê navegação de reviewer" do
    user = User.create!(name: "Revisor", email: "rev@ex.com", password: "senha123", password_confirmation: "senha123", role: :reviewer)
    visit login_path
    fill_in "E-mail", with: user.email
    fill_in "Senha", with: "senha123"
    click_button "Entrar"
    expect(page).to have_link("Tarefas em Revisão", href: reviewer_reviews_path)
    expect(page).not_to have_link("Imagens", exact: true)
    expect(page).not_to have_link("Upload de Tile")
    expect(page).not_to have_link("Upload de Imagem")
    expect(page).not_to have_link("Exportar Dataset")
    expect(page).not_to have_link("Tarefas Disponíveis")
    expect(page).not_to have_link("Tarefa Atual")
    expect(page).not_to have_link("Minhas Tarefas")
  end
end
