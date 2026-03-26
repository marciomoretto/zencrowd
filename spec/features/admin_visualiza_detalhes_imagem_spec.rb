require 'rails_helper'

RSpec.describe 'Admin visualiza detalhes de imagem', type: :feature do
  let!(:admin) { create(:user, :admin) }
  let!(:annotator) { create(:user, :annotator) }

  let(:preview_filename) { "integracao_preview_#{SecureRandom.hex(6)}.png" }
  let(:preview_relative_path) { "storage/uploads/images/#{preview_filename}" }
  let(:preview_absolute_path) { Rails.root.join(preview_relative_path) }

  let!(:image_with_preview) do
    create(
      :tile,
      original_filename: 'imagem_integracao_show.png',
      storage_path: preview_relative_path,
      status: :reserved,
      task_value: 12.5,
      uploader: admin,
      reserver: annotator,
      reserved_at: Time.current
    )
  end

  let!(:image_without_preview) do
    create(
      :tile,
      original_filename: 'imagem_sem_preview.jpg',
      storage_path: Rails.root.join('tmp', 'spec', 'images', 'inexistente.jpg').to_s,
      status: :available,
      task_value: 7.0,
      uploader: admin
    )
  end

  let!(:imagem_associada_ao_tile) do
    imagem = create(:imagem)
    create(:imagem_tile, imagem: imagem, tile: image_with_preview)
    imagem
  end

  before do
    FileUtils.mkdir_p(preview_absolute_path.dirname)
    File.binwrite(preview_absolute_path, 'fake image data')
  end

  after do
    File.delete(preview_absolute_path) if File.exist?(preview_absolute_path)
  end

  def login_as(user)
    visit login_path
    fill_in 'E-mail', with: user.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'
  end

  scenario 'admin abre detalhes clicando no nome do arquivo no index' do
    login_as(admin)

    visit tiles_path

    expect(page).to have_link(image_with_preview.original_filename, href: tile_path(image_with_preview))
    expect(page).to have_content('Imagem associada')
    expect(page).to have_link(imagem_associada_ao_tile.arquivo.filename.to_s, href: imagem_path(imagem_associada_ao_tile))

    click_link image_with_preview.original_filename

    expect(page).to have_current_path(tile_path(image_with_preview))
    expect(page).to have_content("Tile #{image_with_preview.id}")
    expect(page).to have_content('Reservada')
    expect(page).to have_content(admin.name)
    expect(page).to have_content(annotator.name)
    expect(page).to have_content('Imagem associada')
    expect(page).to have_link(imagem_associada_ao_tile.arquivo.filename.to_s, href: imagem_path(imagem_associada_ao_tile))
    expect(page).to have_selector("img[alt='#{image_with_preview.original_filename}']")
    expect(page).to have_selector("img[src*='#{preview_tile_path(image_with_preview)}']")
  end

  scenario 'admin vê mensagem de preview indisponível quando arquivo não existe' do
    login_as(admin)

    visit tile_path(image_without_preview)

    expect(page).to have_content("Tile #{image_without_preview.id}")
    expect(page).to have_content('Preview não disponível para este arquivo.')
    expect(page).to have_content('Disponível')
  end

  scenario 'admin atualiza apenas o valor da tarefa no show' do
    login_as(admin)

    visit tile_path(image_with_preview)

    expect(page).to have_button('R$ 12,50')
    expect(page).to have_content('Reservada')
    expect(page).not_to have_selector('select#image_status', visible: :all)

    fill_in 'tile_task_value', with: '30.25', visible: :all
    click_button 'Salvar'

    expect(page).to have_current_path(tile_path(image_with_preview))
    expect(page).to have_content('Tile atualizado com sucesso.')
    expect(page).to have_content('Reservada')
    expect(page).to have_content('R$ 30,25')

    image_with_preview.reload
    expect(image_with_preview.status).to eq('reserved')
    expect(image_with_preview.task_value.to_f).to eq(30.25)
  end

  scenario 'admin remove imagem a partir do show' do
    login_as(admin)

    visit tile_path(image_with_preview)

    expect(page).to have_button('Remover')
    expect(page).to have_selector("form[data-turbo-confirm='Tem certeza que deseja remover este tile? Essa ação não pode ser desfeita.']")

    expect do
      click_button 'Remover'
    end.to change(Image, :count).by(-1)

    expect(page).to have_current_path(tiles_path)
    expect(page).to have_content('Tile removido com sucesso.')
  end

  scenario 'annotator acessa detalhes em modo somente leitura' do
    login_as(annotator)

    visit tile_path(image_with_preview)

    expect(page).to have_current_path(tile_path(image_with_preview))
    expect(page).to have_content("Tile #{image_with_preview.id}")
    expect(page).to have_content('ID')
    expect(page).to have_content('Arquivo')
    expect(page).to have_content('Valor da tarefa')
    expect(page).to have_content('R$ 12,50')

    expect(page).not_to have_content('Status')
    expect(page).not_to have_content('Cabeças estimadas')
    expect(page).not_to have_button('Salvar')
    expect(page).not_to have_button('Contar cabeças')
    expect(page).not_to have_button('Remover')
    expect(page).not_to have_selector("#task-value-display-#{image_with_preview.id}")
    expect(page).not_to have_field('tile_task_value', visible: :all)
  end

  scenario 'annotator não pode acessar listagem de tiles' do
    login_as(annotator)

    visit tiles_path

    expect(page).to have_current_path(dashboard_path)
    expect(page).to have_content('Permissão negada')
  end
end
