require 'rails_helper'

RSpec.describe 'Visitor access restrictions', type: :feature do
  let!(:visitor) do
    create(
      :user,
      :visitor,
      email: 'visitor.feature@example.com',
      password: 'password123',
      password_confirmation: 'password123',
      onboarding_completed: true
    )
  end

  scenario 'visitor logs in and is redirected to meus dados' do
    visit '/login'
    fill_in 'E-mail', with: visitor.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'

    expect(page).to have_current_path(meus_dados_path)
  end

  scenario 'visitor cannot access dashboard and is redirected to meus dados' do
    visit '/login'
    fill_in 'E-mail', with: visitor.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'

    visit dashboard_path

    expect(page).to have_current_path(meus_dados_path)
    expect(page).to have_content('Permissão negada')
  end
end
