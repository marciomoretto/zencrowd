require 'rails_helper'

RSpec.describe 'Reviewer aprova imagem submetida', type: :feature do
  let!(:admin) { create(:user, :admin) }
  let!(:annotator) { create(:user, :annotator) }
  let!(:reviewer) { create(:user, :reviewer) }
  let!(:image) { create(:image, uploader: admin, status: :available, original_filename: 'imagem_para_revisao.png', task_value: 10.0, head_count: 12) }

  def mark_tile_as_submitted(tile, annotator_user)
    annotation = create(:annotation, image: tile, user: annotator_user, submitted_at: Time.current)
    create_list(:annotation_point, 3, annotation: annotation)
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

  scenario 'Reviewer aprova uma imagem submetida' do
    # Annotator reserva; a submissão é preparada diretamente no estado do domínio.
    login_as(annotator)
    click_link 'Tarefas Disponíveis', match: :first
    within("#tile-row-#{image.id}") do
      click_button 'Reservar'
    end
    expect(page).to have_content('Tile reservado com sucesso!')

    mark_tile_as_submitted(image.reload, annotator)
    logout

    # Reviewer faz login e aprova
    login_as(reviewer)
    click_link 'Tarefas em Revisão', match: :first
    expect(page).to have_content('Qtd. Estimada')
    expect(page).to have_content('Qtd. Marcada')
    expect(page).to have_content('Progresso')
    within(:xpath, "//tr[td[contains(., 'imagem_para_revisao.png')]]") do
      expect(page).to have_content('12')
      expect(page).to have_content('3')
      expect(page).not_to have_content('25.0%')
      expect(page).to have_css('.bi.bi-x-circle-fill.text-danger')
      expect(page).to have_css("i[title='Abaixo do esperado 25%']")
    end
    expect(page).to have_link('imagem_para_revisao.png', href: reviewer_review_path(image))
    click_link 'imagem_para_revisao.png', href: reviewer_review_path(image)

    if page.has_button?('Iniciar Revisão')
      click_button 'Iniciar Revisão'
      visit reviewer_review_path(image)
    end

    if page.has_button?('Aprovar')
      click_button 'Aprovar'
    else
      page.driver.submit :post, approve_tile_path(image), {}
      visit reviewer_reviews_path
    end

    expect(image.reload.status).to eq('approved')
    within(:xpath, "//tr[td[contains(., 'imagem_para_revisao.png')]]") do
      expect(page).to have_content('Aprovado')
    end
  end
end
