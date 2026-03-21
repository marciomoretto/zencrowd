require 'rails_helper'

RSpec.describe 'Annotator não pode reservar duas imagens', type: :feature do
  let!(:admin) { create(:user, :admin) }
  let!(:annotator) { create(:user, :annotator) }
  let!(:image1) { create(:image, uploader: admin, status: :available, original_filename: 'imagem1.png', task_value: 5.0) }
  let!(:image2) { create(:image, uploader: admin, status: :available, original_filename: 'imagem2.png', task_value: 7.0) }

  scenario 'Annotator tenta reservar duas imagens e é bloqueado' do
    visit '/login'
    fill_in 'E-mail', with: annotator.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'

    click_link 'Tarefas Disponíveis', match: :first
    expect(page).to have_content('imagem1.png')
    expect(page).to have_content('imagem2.png')
    within("#tile-row-#{image1.id}") do
      click_button 'Reservar'
    end

    expect(page).to have_content('Tile reservado com sucesso!')
    expect(page).to have_content('Tarefa Atual')
    expect(page).to have_content('Editor de Pontos (ZenPlot)')
    expect(page).to have_css('[data-wpd-app]')

    # Tentar reservar outra imagem
    visit available_tiles_path
    expect(page).to have_content('Você já possui uma tarefa reservada')
    expect(page).to have_button('Reservar')

    within("#tile-row-#{image2.id}") do
      click_button 'Reservar'
    end

    expect(page).to have_content('Você já possui uma tarefa reservada. Finalize ou desista da tarefa atual antes de reservar outra.')
    expect(image2.reload.status).to eq('available')
  end

  scenario 'Annotator com reserva expirada consegue reservar outra tarefa' do
    image1.update!(
      status: :reserved,
      reserver: annotator,
      reserved_at: 3.days.ago,
      reservation_expires_at: 1.minute.ago
    )

    visit '/login'
    fill_in 'E-mail', with: annotator.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'

    visit available_tiles_path

    expect(page).not_to have_content('Você já possui um tile reservado')
    expect(image1.reload.status).to eq('abandoned')
    expect(image1.reserver).to be_nil

    within("#tile-row-#{image2.id}") do
      click_button 'Reservar'
    end

    expect(page).to have_content('Tile reservado com sucesso!')
    expect(image2.reload.status).to eq('reserved')
    expect(image2.reserver).to eq(annotator)
  end

  scenario 'Annotator com pilha de rejeitadas não pode reservar tarefa nova' do
    create(:tile, uploader: admin, status: :rejected, reserver: annotator, original_filename: 'rejeitada_pendente.png')

    visit '/login'
    fill_in 'E-mail', with: annotator.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'

    visit available_tiles_path
    expect(page).to have_content('tarefa(s) rejeitada(s) pendente(s)')

    within("#tile-row-#{image1.id}") do
      click_button 'Reservar'
    end

    expect(page).to have_content('Você possui tarefas rejeitadas pendentes. Finalize essa pilha antes de reservar novas tarefas.')
    expect(image1.reload.status).to eq('available')
  end
end
