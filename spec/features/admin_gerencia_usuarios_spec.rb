require 'rails_helper'

RSpec.describe 'Admin gerencia usuários', type: :feature do
  scenario 'Admin visualiza usuários, altera papel e bloqueia/desbloqueia acesso' do
    admin = create(:user, :admin, email: 'admin@zencrowd.com')
    annotator = create(:user, :annotator, email: 'ana@zencrowd.com', name: 'Ana')

    visit login_path
    fill_in 'E-mail', with: admin.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'

    click_link 'Usuários', match: :first
    expect(page).to have_content('Gerenciamento de Usuários')
    expect(page).to have_content('Ana')
    expect(page).to have_content('ana@zencrowd.com')

    within("#user-#{annotator.id}") do
      select 'Revisor', from: 'role'
      click_button 'Salvar'
    end

    expect(page).to have_content('Papel de Ana atualizado para reviewer.')
    expect(annotator.reload).to be_reviewer

    within("#user-#{annotator.id}") do
      click_button 'Bloquear'
    end

    expect(page).to have_content('Usuário Ana foi bloqueado.')
    expect(annotator.reload).to be_blocked

    within("#user-#{annotator.id}") do
      click_button 'Desbloquear'
    end

    expect(page).to have_content('Usuário Ana foi desbloqueado.')
    expect(annotator.reload).not_to be_blocked
  end

  scenario 'Usuário bloqueado não consegue fazer login' do
    blocked_user = create(:user, :annotator, email: 'bloqueado@zencrowd.com', blocked: true)

    visit login_path
    fill_in 'E-mail', with: blocked_user.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'

    expect(page).to have_content('Sua conta está bloqueada. Procure um administrador.')
    expect(current_path).to eq(login_path)
  end
end
