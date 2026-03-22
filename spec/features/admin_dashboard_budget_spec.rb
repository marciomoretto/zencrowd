require 'rails_helper'

RSpec.describe 'Admin dashboard orçamento', type: :feature do
  let!(:admin) { create(:user, :admin) }
  let!(:available_tile) { create(:tile, status: :available, task_value: 10.0) }
  let!(:paid_tile) { create(:tile, status: :paid, task_value: 30.0) }
  let!(:reserved_tile) { create(:tile, status: :reserved, task_value: 20.0) }
  let!(:in_review_tile) { create(:tile, status: :in_review, task_value: 15.0) }
  let!(:approved_tile) { create(:tile, status: :approved, task_value: 12.0) }
  let!(:rejected_tile) { create(:tile, status: :rejected, task_value: 8.0) }
  let!(:payment_requested_tile) { create(:tile, status: :payment_requested, task_value: 18.0) }

  before do
    AppSetting.update_operational_settings!(task_value_per_head_cents: 0, task_expiration_hours: 48, budget_limit_reais: 1000)
  end

  scenario 'admin visualiza barra de orçamento no dashboard' do
    paid_total = Tile.where(status: :paid).sum(:task_value).to_d
    to_pay_total = Tile.where(status: %i[reserved submitted in_review approved payment_requested]).sum(:task_value).to_d
    committed_total = paid_total + to_pay_total
    remaining_total = [1000.to_d - committed_total, 0].max

    visit login_path
    fill_in 'E-mail', with: admin.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'

    expect(page).to have_current_path(dashboard_path)
    expect(page).to have_content('Execução do orçamento')
    expect(page).to have_content('Comprometido:')
    expect(page).to have_content(ActionController::Base.helpers.number_to_currency(committed_total, unit: 'R$', separator: ',', delimiter: '.', format: '%u%n'))
    expect(page).to have_content('Pago')
    expect(page).to have_content('A pagar')
    expect(page).to have_content('Restante')
    expect(page).to have_content(ActionController::Base.helpers.number_to_currency(remaining_total, unit: 'R$', separator: ',', delimiter: '.', format: '%u%n'))

    expect(page).to have_content('Progresso')
    expect(page).to have_content('Total:')
    expect(page).to have_content('7')
    expect(page).to have_content('Disponíveis')
    expect(page).to have_content('Reservados')
    expect(page).to have_content('Em revisão')
    expect(page).to have_content('Aprovados')
    expect(page).to have_content('Reprovados')
    expect(page).to have_content('Pagamento solicitado')
    expect(page).to have_content('Pago')
  end
end
