require 'rails_helper'

RSpec.describe 'Admin painel de configurações', type: :feature do
  let!(:admin) { create(:user, :admin) }

  before do
    AppSetting.delete_all
  end

  def login_as(user)
    visit login_path
    fill_in 'E-mail', with: user.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'
  end

  scenario 'admin visualiza os campos com valores padrão' do
    login_as(admin)
    visit admin_settings_path

    expect(page).to have_content('Painel de Configurações')
    expect(page).to have_field('settings_task_value_per_head_cents', with: '0')
    expect(page).to have_field('settings_task_expiration_hours', with: '48')
    expect(page).to have_field('settings_budget_limit_reais', with: '0')
    expect(page).to have_field('settings_min_payment_reais', with: '0')
    expect(page).to have_button('Salvar')
  end

  scenario 'admin atualiza configurações pela interface' do
    login_as(admin)
    visit admin_settings_path

    fill_in 'settings_task_value_per_head_cents', with: '35'
    fill_in 'settings_task_expiration_hours', with: '12'
    fill_in 'settings_budget_limit_reais', with: '15000'
    fill_in 'settings_min_payment_reais', with: '50'
    click_button 'Salvar'

    expect(page).to have_current_path(admin_settings_path)
    expect(page).to have_content('Configurações atualizadas com sucesso.')
    expect(page).to have_field('settings_task_value_per_head_cents', with: '35')
    expect(page).to have_field('settings_task_expiration_hours', with: '12')
    expect(page).to have_field('settings_budget_limit_reais', with: '15000')
    expect(page).to have_field('settings_min_payment_reais', with: '50')
    expect(AppSetting.task_value_per_head_cents).to eq(35)
    expect(AppSetting.task_expiration_hours).to eq(12)
    expect(AppSetting.budget_limit_reais).to eq(15000)
    expect(AppSetting.min_payment_reais).to eq(50)
  end
end
