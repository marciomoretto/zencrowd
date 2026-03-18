require 'rails_helper'

RSpec.feature "Navigation", type: :feature do
  scenario "Usuário não autenticado vê apenas login e cadastro" do
    visit root_path
    save_and_open_page
    expect(page).to have_link("Entrar", href: login_path)
    expect(page).to have_link("Cadastrar", href: signup_path)
    expect(page).not_to have_link("Imagens", exact: true)
    expect(page).not_to have_link("Upload de Imagem")
    expect(page).not_to have_link("Exportar Dataset")
    expect(page).not_to have_link("Imagens Disponíveis")
    expect(page).not_to have_link("Minha Tarefa")
    expect(page).not_to have_link("Tarefas em Revisão")
  end

  scenario "Admin vê navegação de admin" do
    admin = User.create!(name: "Admin", email: "admin@ex.com", password: "senha123", password_confirmation: "senha123", role: :admin)
    visit login_path
    save_and_open_page
    fill_in "E-mail", with: admin.email
    fill_in "Senha", with: "senha123"
    click_button "Entrar"
    expect(page).to have_link("Imagens", href: images_path)
    expect(page).to have_link("Upload de Imagem", href: new_image_path)
    expect(page).to have_link("Exportar Dataset", href: export_dataset_path)
    expect(page).not_to have_link("Imagens Disponíveis")
    expect(page).not_to have_link("Minha Tarefa")
    expect(page).not_to have_link("Tarefas em Revisão")
  end

  scenario "Annotator vê navegação de annotator" do
    user = User.create!(name: "Ana", email: "ana@ex.com", password: "senha123", password_confirmation: "senha123", role: :annotator)
    visit login_path
    save_and_open_page
    fill_in "E-mail", with: user.email
    fill_in "Senha", with: "senha123"
    click_button "Entrar"
    expect(page).to have_link("Imagens Disponíveis", href: available_images_path)
    expect(page).to have_link("Minha Tarefa", href: my_task_path)
    expect(page).not_to have_link("Imagens", exact: true)
    expect(page).not_to have_link("Upload de Imagem")
    expect(page).not_to have_link("Exportar Dataset")
    expect(page).not_to have_link("Tarefas em Revisão")
  end

  scenario "Reviewer vê navegação de reviewer" do
    user = User.create!(name: "Revisor", email: "rev@ex.com", password: "senha123", password_confirmation: "senha123", role: :reviewer)
    visit login_path
    save_and_open_page
    fill_in "E-mail", with: user.email
    fill_in "Senha", with: "senha123"
    click_button "Entrar"
    expect(page).to have_link("Tarefas em Revisão", href: reviewer_reviews_path)
    expect(page).not_to have_link("Imagens", exact: true)
    expect(page).not_to have_link("Upload de Imagem")
    expect(page).not_to have_link("Exportar Dataset")
    expect(page).not_to have_link("Imagens Disponíveis")
    expect(page).not_to have_link("Minha Tarefa")
  end
end
