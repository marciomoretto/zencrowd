require 'rails_helper'

RSpec.describe 'Roteamento público x logado', type: :feature do
  scenario 'visitante é redirecionado de /dashboard para /login' do
    visit dashboard_path

    expect(current_path).to eq(login_path)
    expect(page).to have_content('Você precisa estar logado para acessar esta página.')
  end

  scenario 'usuário autenticado é redirecionado da landing para /dashboard' do
    user = create(:user, :annotator, email: 'annotator-routing@example.com')

    visit login_path
    fill_in 'E-mail', with: user.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'

    visit root_path

    expect(current_path).to eq(dashboard_path)
    expect(page).to have_content("Olá, #{user.name}!")
  end

  scenario 'login bem-sucedido redireciona para /dashboard' do
    user = create(:user, :reviewer, email: 'reviewer-routing@example.com')

    visit login_path
    fill_in 'E-mail', with: user.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'

    expect(current_path).to eq(dashboard_path)
  end
end
