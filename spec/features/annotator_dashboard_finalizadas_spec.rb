require 'rails_helper'

RSpec.describe 'Annotator dashboard com minhas tarefas', type: :feature do
  let!(:admin) { create(:user, :admin) }
  let!(:annotator) { create(:user, :annotator) }
  let!(:other_annotator) { create(:user, :annotator) }

  scenario 'dashboard e aba listam apenas tarefas do annotator logado' do
    own_paid_tile = create(:tile, uploader: admin, status: :paid, original_filename: 'tile_pago.jpg', task_value: 12.5)
    own_to_pay_tile = create(:tile, uploader: admin, status: :approved, original_filename: 'tile_a_pagar.jpg', task_value: 7.5)
    other_tile = create(:tile, uploader: admin, status: :paid, original_filename: 'tile_outro.jpg', task_value: 99.0)

    own_paid_annotation = create(:annotation, image: own_paid_tile, user: annotator, submitted_at: 1.hour.ago)
    create_list(:annotation_point, 3, annotation: own_paid_annotation)
    own_to_pay_annotation = create(:annotation, image: own_to_pay_tile, user: annotator, submitted_at: 30.minutes.ago)
    create_list(:annotation_point, 2, annotation: own_to_pay_annotation)
    create(:annotation, image: other_tile, user: other_annotator, submitted_at: 2.hours.ago)

    visit '/login'
    fill_in 'E-mail', with: annotator.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'

    expect(page).to have_current_path(dashboard_path)
    expect(page).to have_content('Minhas Tarefas')
    click_link 'Minhas Tarefas', match: :first

    expect(page).to have_current_path(completed_tasks_path)
    expect(page).to have_content('Minhas Tarefas')
    expect(page).to have_content('Total recebido')
    expect(page).to have_content('Total a receber')
    expect(page).to have_content('Valor')
    expect(page).to have_content('Total de Pontos')
    expect(page).to have_content('tile_pago.jpg')
    expect(page).to have_content('tile_a_pagar.jpg')
    expect(page).to have_content('R$12,50')
    expect(page).to have_content('R$7,50')
    expect(page).to have_content('3')
    expect(page).to have_content('2')
    expect(page).not_to have_content('tile_outro.jpg')
  end

  scenario 'aba mostra estado vazio quando annotator não finalizou tarefas' do
    visit '/login'
    fill_in 'E-mail', with: annotator.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'

    expect(page).to have_current_path(dashboard_path)
    expect(page).to have_content('Minhas Tarefas')
    click_link 'Minhas Tarefas', match: :first
    expect(page).to have_current_path(completed_tasks_path)
    expect(page).to have_content('Você ainda não finalizou nenhuma tarefa.')
  end

  scenario 'annotator vê card de contas e solicita pagamento quando atinge mínimo' do
    AppSetting.update_operational_settings!(
      task_value_per_head_cents: 0,
      task_expiration_hours: 48,
      budget_limit_reais: 0,
      min_payment_reais: 10
    )

    approved_tile_1 = create(:tile, uploader: admin, status: :approved, original_filename: 'tile_aprovado_1.jpg', task_value: 7.0)
    approved_tile_2 = create(:tile, uploader: admin, status: :approved, original_filename: 'tile_aprovado_2.jpg', task_value: 8.0)

    create(:annotation, image: approved_tile_1, user: annotator, submitted_at: 1.hour.ago)
    create(:annotation, image: approved_tile_2, user: annotator, submitted_at: 30.minutes.ago)

    visit '/login'
    fill_in 'E-mail', with: annotator.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'

    expect(page).to have_current_path(dashboard_path)
    expect(page).to have_content('Contas do annotator')
    expect(page).to have_content('Tarefas aprovadas')
    expect(page).to have_content('tile_aprovado_1.jpg')
    expect(page).to have_content('tile_aprovado_2.jpg')
    expect(page).to have_content('Total aprovado')
    expect(page).to have_content('Pagamento solicitado')
    expect(page).to have_content('Total a receber')
    expect(page).to have_content('R$15,00')

    click_button 'Requerer pagamento'

    expect(page).to have_current_path(dashboard_path)
    expect(page).to have_content('Solicitação de pagamento registrada com sucesso')
    expect(page).to have_content('R$0,00')
    expect(page).to have_content('R$15,00')
    expect(approved_tile_1.reload.status).to eq('payment_requested')
    expect(approved_tile_2.reload.status).to eq('payment_requested')
  end

  scenario 'botão de requerer pagamento fica bloqueado abaixo do mínimo' do
    AppSetting.update_operational_settings!(
      task_value_per_head_cents: 0,
      task_expiration_hours: 48,
      budget_limit_reais: 0,
      min_payment_reais: 20
    )

    approved_tile = create(:tile, uploader: admin, status: :approved, original_filename: 'tile_aprovado_abaixo_min.jpg', task_value: 12.0)
    create(:annotation, image: approved_tile, user: annotator, submitted_at: 20.minutes.ago)

    visit '/login'
    fill_in 'E-mail', with: annotator.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'

    expect(page).to have_current_path(dashboard_path)
    expect(page).to have_button('Requerer pagamento', disabled: true)
  end
end
