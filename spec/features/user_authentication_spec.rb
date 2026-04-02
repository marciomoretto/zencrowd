require 'rails_helper'

RSpec.feature "UserAuthentication", type: :feature do
  scenario "Página de login é exibida" do
    visit login_path

    expect(page).to have_field("E-mail")
    expect(page).to have_field("Senha")
    expect(page).to have_button("Entrar")
  end

  scenario "Usuário realiza login com sucesso" do
    User.create!(name: "Maria Login", email: "maria@example.com", password: "senha456", password_confirmation: "senha456", role: :reviewer)

    visit login_path
    fill_in "E-mail", with: "maria@example.com"
    fill_in "Senha", with: "senha456"
    click_button "Entrar"

    expect(page).to have_content("Login realizado com sucesso")
    expect(page).to have_content("Maria Login")
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
    expect(page).to have_content("Logout Test")
    click_on "Sair"
    expect(page).to have_content("Logout realizado com sucesso")
    expect(page).to have_link("Entrar")
  end
end
