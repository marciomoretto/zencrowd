require 'rails_helper'

RSpec.feature "UserAuthentication", type: :feature do
  scenario "Usuário realiza cadastro com sucesso" do
    visit signup_path

    fill_in "Nome", with: "João Teste"
    fill_in "E-mail", with: "joao@example.com"
    fill_in "Senha", with: "senha123"
    fill_in "Confirme a Senha", with: "senha123"
    select "Anotador", from: "Papel"
    click_button "Criar Conta"

    expect(page).to have_content("Cadastro realizado com sucesso")
    expect(page).to have_content("Olá, João Teste!")
  end

  scenario "Usuário realiza login com sucesso" do
    User.create!(name: "Maria Login", email: "maria@example.com", password: "senha456", password_confirmation: "senha456", role: :reviewer)

    visit login_path
    fill_in "E-mail", with: "maria@example.com"
    fill_in "Senha", with: "senha456"
    click_button "Entrar"

    expect(page).to have_content("Login realizado com sucesso")
    expect(page).to have_content("Olá, Maria Login!")
  end

  scenario "Cadastro inválido exibe erros" do
    visit signup_path
    click_button "Criar Conta"
    save_page('tmp/cadastro_invalido.html') # Salva o HTML para inspeção
    expect(page).to have_content("Nome não pode ficar em branco")
    expect(page).to have_content("E-mail não pode ficar em branco")
    expect(page).to have_content("Senha não pode ficar em branco")
    expect(page).to have_content("Papel não pode ficar em branco")
  end

  scenario "Login inválido exibe erro" do
    visit login_path
    fill_in "E-mail", with: "naoexiste@example.com"
    fill_in "Senha", with: "errada"
    click_button "Entrar"
    expect(page).to have_content("Email ou senha inválidos")
  end

  scenario "Usuário faz logout" do
    user = User.create!(name: "Logout Test", email: "logout@example.com", password: "logoutpass", password_confirmation: "logoutpass", role: :annotator)
    visit login_path
    fill_in "E-mail", with: user.email
    fill_in "Senha", with: "logoutpass"
    click_button "Entrar"
    expect(page).to have_content("Olá, Logout Test!")
    click_on "Sair"
    expect(page).to have_content("Logout realizado com sucesso")
    expect(page).to have_link("Entrar")
  end
end
