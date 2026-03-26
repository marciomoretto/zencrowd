require 'rails_helper'

RSpec.describe 'Annotator visualiza tarefa reservada', type: :feature do
  let!(:admin) { create(:user, :admin) }
  let!(:annotator) { create(:user, :annotator) }
  let!(:outra_annotator) { create(:user, :annotator) }
  let!(:image) { create(:image, uploader: admin, status: :reserved, reserver: annotator, original_filename: 'imagem_tarefa.jpg', task_value: 12.5, storage_path: Rails.root.join('spec/fixtures/files/test_image.jpg')) }

  scenario 'Annotator vê sua imagem reservada com dados e preview' do
    visit '/login'
    fill_in 'E-mail', with: annotator.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'
    click_link 'Tarefa Atual', match: :first
    expect(page).to have_content('Tarefa Atual')
    expect(page).to have_content('Editor de Pontos (ZenPlot)')
    expect(page).to have_css('[data-wpd-app]')
    expect(page).to have_button('Desistir')
    expect(page).to have_button('Salvar')
    expect(page).to have_button('Enviar')
  end

  scenario 'Annotator sem imagem reservada vê mensagem e link' do
    visit '/login'
    fill_in 'E-mail', with: outra_annotator.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'
    click_link 'Tarefa Atual', match: :first
    expect(page).to have_content('Nenhuma tarefa reservada')
    expect(page).to have_link('Ver tarefas disponíveis')
  end

  scenario 'Annotator não acessa tarefa de outro usuário' do
    visit '/login'
    fill_in 'E-mail', with: outra_annotator.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'
    visit my_task_path
    expect(page).not_to have_content(image.id)
    expect(page).to have_content('Nenhuma tarefa reservada')
  end

  scenario 'Annotator desiste da tarefa e tile volta para disponível' do
    visit '/login'
    fill_in 'E-mail', with: annotator.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'

    click_link 'Tarefa Atual', match: :first
    click_button 'Desistir'

    expect(page).to have_current_path(available_tiles_path)
    expect(page).to have_content('Você desistiu da tarefa. O tile foi marcado como abandonado e voltou para a fila disponível.')
    expect(image.reload.status).to eq('abandoned')
    expect(image.reserver).to be_nil
    expect(image.reserved_at).to be_nil
  end

  scenario 'Reserva expirada é liberada automaticamente e some da tarefa atual' do
    image.update!(
      reserved_at: 3.days.ago,
      reservation_expires_at: 1.minute.ago
    )

    visit '/login'
    fill_in 'E-mail', with: annotator.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'

    visit my_task_path

    expect(page).to have_content('Nenhuma tarefa reservada')
    expect(image.reload.status).to eq('abandoned')
    expect(image.reserver).to be_nil
    expect(image.reserved_at).to be_nil
    expect(image.reservation_expires_at).to be_nil
  end
end
