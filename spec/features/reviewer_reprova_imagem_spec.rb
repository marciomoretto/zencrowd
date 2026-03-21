require 'rails_helper'

RSpec.describe 'Reviewer reprova imagem submetida', type: :feature do
  let!(:admin) { create(:user, :admin) }
  let!(:annotator) { create(:user, :annotator) }
  let!(:reviewer) { create(:user, :reviewer) }
  let!(:image) { create(:image, uploader: admin, status: :available, original_filename: 'imagem_para_revisao.png', task_value: 10.0) }

  def mark_tile_as_submitted(tile, annotator_user)
    create(:annotation, image: tile, user: annotator_user, submitted_at: Time.current)
    tile.update!(status: :submitted)
  end

  def login_as(user)
    visit login_path
    fill_in 'E-mail', with: user.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'
  end

  def logout
    page.driver.submit :delete, logout_path, {}
  end

  scenario 'Reviewer reprova uma imagem submetida' do
    # Annotator reserva; a submissão é preparada diretamente no estado do domínio.
    login_as(annotator)
    click_link 'Tarefas Disponíveis'
    within("#tile-row-#{image.id}") do
      click_button 'Reservar'
    end
    expect(page).to have_content('Tile reservado com sucesso!')

    mark_tile_as_submitted(image.reload, annotator)
    logout

    # Reviewer faz login e reprova
    login_as(reviewer)
    click_link 'Tarefas em Revisão'
    expect(page).to have_content('imagem_para_revisao.png')
    if page.has_button?('Iniciar Revisão')
      click_button 'Iniciar Revisão'
      visit current_path
    end

    click_link 'Revisar', href: reviewer_review_path(image)
    click_button 'Reprovar'

    expect(page).to have_content('Tile devolvido para anotação').or have_content('reservada')
    # A imagem deve sumir da lista de revisão
    expect(page).not_to have_content('imagem_para_revisao.png')
    expect(image.reload.status).to eq('reserved')
    expect(image.reserver).to eq(annotator)

    # Annotator volta a ter a tarefa como reservada para nova anotação.
    logout
    login_as(annotator)
    click_link 'Tarefa Atual'
    expect(page).to have_content('Tarefa Atual')
    expect(page).to have_css('[data-wpd-app]')
  end
end
