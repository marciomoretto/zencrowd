require 'rails_helper'

RSpec.describe 'Annotator dashboard com tarefas finalizadas', type: :feature do
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
    expect(page).to have_content('Tarefas Finalizadas')
    click_link 'Tarefas Finalizadas', match: :first

    expect(page).to have_current_path(completed_tasks_path)
    expect(page).to have_content('Tarefas Finalizadas')
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
    expect(page).to have_content('Tarefas Finalizadas')
    click_link 'Tarefas Finalizadas', match: :first
    expect(page).to have_current_path(completed_tasks_path)
    expect(page).to have_content('Você ainda não finalizou nenhuma tarefa.')
  end
end
