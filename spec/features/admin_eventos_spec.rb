require 'rails_helper'

RSpec.describe 'Admin gerencia eventos', type: :feature do
  def login_as(user)
    visit login_path
    fill_in 'E-mail', with: user.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'
  end

  scenario 'admin cria evento e envia imagem vinculada automaticamente' do
    admin = create(:user, :uploader)

    login_as(admin)

    visit new_uploader_evento_path

    fill_in 'Nome', with: 'Evento de Teste'
    select 'Direita', from: 'Categoria'
    fill_in 'evento_nova_pasta_form', with: 'Pasta Inicial'
    attach_file 'evento_arquivo', Rails.root.join('spec/fixtures/files/sample.jpg')
    click_button 'Salvar'

    evento = Evento.order(:id).last
    imagem = evento.imagens.order(:id).last

    expect(page).to have_content('Evento criado com sucesso.')
    expect(page).to have_content('Evento de Teste')
    expect(evento.nome).to eq('Evento de Teste')
    expect(evento.categoria).to eq('direita')
    expect(evento.imagens.count).to eq(1)
    expect(imagem.arquivo.filename.to_s).to eq('sample.jpg')
    expect(imagem.evento).to eq(evento)
    expect(imagem.pasta).to eq('Pasta Inicial')
  end

  scenario 'admin cria evento com upload multiplo de imagens' do
    admin = create(:user, :uploader)

    login_as(admin)

    visit new_uploader_evento_path

    fill_in 'Nome', with: 'Evento com Upload Multiplo'
    fill_in 'evento_nova_pasta_form', with: 'Pasta Multipla'
    attach_file 'evento_arquivo', [
      Rails.root.join('spec/fixtures/files/sample.jpg'),
      Rails.root.join('spec/fixtures/files/sample2.jpg')
    ]
    click_button 'Salvar'

    evento = Evento.order(:id).last

    expect(page).to have_content('Evento criado com sucesso.')
    expect(evento.imagens.count).to eq(2)
    expect(evento.imagens.order(:id).map { |imagem| imagem.arquivo.filename.to_s }).to include('sample.jpg', 'sample2.jpg')
    expect(evento.imagens.pluck(:pasta).uniq).to eq(['Pasta Multipla'])
  end

  scenario 'admin cria evento e define nova pasta para imagem enviada' do
    admin = create(:user, :uploader)

    login_as(admin)

    visit new_uploader_evento_path

    fill_in 'Nome', with: 'Evento Pasta Nova'
    fill_in 'evento_nova_pasta_form', with: 'Pasta Nova'
    attach_file 'evento_arquivo', Rails.root.join('spec/fixtures/files/sample.jpg')
    click_button 'Salvar'

    evento = Evento.order(:id).last
    imagem = evento.imagens.order(:id).last

    expect(page).to have_content('Evento criado com sucesso.')
    expect(imagem.pasta).to eq('Pasta Nova')
  end

  scenario 'admin edita evento e envia nova imagem vinculada' do
    admin = create(:user, :uploader)
    evento = create(:evento, nome: 'Evento Antigo', categoria: :esquerda)
    imagem1 = create(:imagem, evento: evento)

    login_as(admin)

    visit edit_uploader_evento_path(evento)

    fill_in 'Nome', with: 'Evento Atualizado'
    select 'Outro', from: 'Categoria'
    fill_in 'evento_nova_pasta_form', with: 'Pasta Atualizada'
    attach_file 'evento_arquivo', Rails.root.join('spec/fixtures/files/sample2.jpg')
    click_button 'Salvar'

    expect(page).to have_content('Evento atualizado com sucesso.')

    evento.reload
    expect(evento.nome).to eq('Evento Atualizado')
    expect(evento.categoria).to eq('outro')
    expect(imagem1.reload.evento).to eq(evento)
    expect(evento.imagens.count).to eq(2)
    expect(evento.imagens.order(:id).last.arquivo.filename.to_s).to eq('sample2.jpg')
    expect(evento.imagens.order(:id).last.pasta).to eq('Pasta Atualizada')
  end

  scenario 'admin remove evento e desassocia imagens' do
    admin = create(:user, :uploader)
    evento = create(:evento, nome: 'Evento para Remocao')
    imagem = create(:imagem, evento: evento)

    login_as(admin)

    visit uploader_eventos_path

    click_link 'Evento para Remocao'
    click_button 'Remover'

    expect(page).to have_content('Evento Evento para Remocao removido com sucesso.')
    expect(Evento.exists?(evento.id)).to be(false)
    expect(imagem.reload.evento).to be_nil
  end

  scenario 'admin edita nome e categoria inline no show do evento' do
    admin = create(:user, :uploader)
    evento = create(:evento, nome: 'Evento Inline', categoria: :direita, data: Date.new(2025, 9, 7), cidade: 'Campinas', local: 'Rua A')

    login_as(admin)

    visit uploader_evento_path(evento)

    expect(page).to have_selector(
      "[data-evento-inline='categoria'] [data-inline-edit-target='display'].evento-categoria-direita",
      text: 'Direita'
    )

    find("[data-evento-inline='nome'] [data-inline-edit-target='display']").click
    fill_in 'evento_nome', with: 'Evento Inline Atualizado'
    click_button 'Salvar nome'

    expect(page).to have_content('Evento atualizado com sucesso.')
    expect(page).to have_content('Evento Inline Atualizado')

    find("[data-evento-inline='categoria'] [data-inline-edit-target='display']").click
    select 'Esquerda', from: 'evento_categoria'
    click_button 'Salvar categoria'

    expect(page).to have_content('Evento atualizado com sucesso.')
    expect(page).to have_content('Esquerda')
    expect(page).to have_selector(
      "[data-evento-inline='categoria'] [data-inline-edit-target='display'].btn-danger",
      text: 'Esquerda'
    )

    find("[data-evento-inline='data'] [data-inline-edit-target='display']").click
    fill_in 'evento_data', with: '2026-09-07'
    click_button 'Salvar data'

    expect(page).to have_content('Evento atualizado com sucesso.')
    expect(page).to have_selector(
      "[data-evento-inline='data'] [data-inline-edit-target='display']",
      text: '07/09/2026'
    )

    find("[data-evento-inline='cidade'] [data-inline-edit-target='display']").click
    fill_in 'evento_cidade', with: 'Sao Paulo'
    click_button 'Salvar cidade'

    expect(page).to have_content('Evento atualizado com sucesso.')
    expect(page).to have_selector(
      "[data-evento-inline='cidade'] [data-inline-edit-target='display']",
      text: 'Sao Paulo'
    )

    find("[data-evento-inline='local'] [data-inline-edit-target='display']").click
    fill_in 'evento_local', with: 'Avenida Paulista'
    click_button 'Salvar local'

    expect(page).to have_content('Evento atualizado com sucesso.')
    expect(page).to have_selector(
      "[data-evento-inline='local'] [data-inline-edit-target='display']",
      text: 'Avenida Paulista'
    )

    evento.reload
    expect(evento.nome).to eq('Evento Inline Atualizado')
    expect(evento.categoria).to eq('esquerda')
    expect(evento.data).to eq(Date.new(2026, 9, 7))
    expect(evento.cidade).to eq('Sao Paulo')
    expect(evento.local).to eq('Avenida Paulista')
  end

  scenario 'admin faz upload no show e preenche cidade/local do evento quando estao nao informados' do
    admin = create(:user, :uploader)
    evento = create(:evento, nome: 'Evento Upload Show', categoria: :direita, data: nil, cidade: 'Nao informada', local: 'Nao informado')

    allow(ImagemMetadataExtractor).to receive(:extract).and_return(
      normalized: {
        data_hora: Time.zone.parse('2025-09-07 11:30:00'),
        cidade: 'Sao Paulo',
        local: 'Avenida Paulista',
        gps_location: '-23.550520,-46.633308'
      },
      exif: { 'datetimeoriginal' => '2025:09:07 11:30:00' },
      xmp: {}
    )

    login_as(admin)

    visit uploader_evento_path(evento)

    fill_in 'evento_nova_pasta_show', with: 'Pasta Endereco Fixo'
    attach_file 'Imagem(ns)', Rails.root.join('spec/fixtures/files/sample2.jpg')
    click_button 'Enviar imagem'

    expect(page).to have_content('Evento atualizado com sucesso.')

    evento.reload
    expect(evento.categoria).to eq('direita')
    expect(evento.data).to eq(Date.new(2025, 9, 7))
    expect(evento.cidade).to eq('Sao Paulo')
    expect(evento.local).to eq('Avenida Paulista')
    expect(evento.imagens.count).to eq(1)
    expect(evento.imagens.order(:id).last.arquivo.filename.to_s).to eq('sample2.jpg')
  end

  scenario 'admin faz upload no show e copia cidade/local do evento para a imagem quando extracao nao informa' do
    admin = create(:user, :uploader)
    evento = create(:evento, nome: 'Evento Origem Endereco', categoria: :direita, cidade: 'Campinas', local: 'Rua A')

    allow(ImagemMetadataExtractor).to receive(:extract).and_return(
      normalized: {
        cidade: 'Nao informada',
        local: 'Nao informado',
        gps_location: '0.000000,0.000000'
      },
      exif: {},
      xmp: {}
    )

    login_as(admin)

    visit uploader_evento_path(evento)

    fill_in 'evento_nova_pasta_show', with: 'Pasta Origem Endereco'
    attach_file 'Imagem(ns)', Rails.root.join('spec/fixtures/files/sample2.jpg')
    click_button 'Enviar imagem'

    expect(page).to have_content('Evento atualizado com sucesso.')

    imagem = evento.imagens.order(:id).last

    expect(imagem.cidade).to eq('Campinas')
    expect(imagem.local).to eq('Rua A')
    expect(evento.reload.cidade).to eq('Campinas')
    expect(evento.reload.local).to eq('Rua A')
  end

  scenario 'admin faz upload no show sem sobrescrever cidade/local ja preenchidos no evento' do
    admin = create(:user, :uploader)
    evento = create(:evento, nome: 'Evento Endereco Fixo', categoria: :esquerda, data: Date.new(2024, 12, 25), cidade: 'Campinas', local: 'Rua A')

    allow(ImagemMetadataExtractor).to receive(:extract).and_return(
      normalized: {
        data_hora: Time.zone.parse('2030-01-01 10:00:00'),
        cidade: 'Sao Paulo',
        local: 'Avenida Paulista',
        gps_location: '-23.550520,-46.633308'
      },
      exif: { 'datetimeoriginal' => '2030:01:01 10:00:00' },
      xmp: {}
    )

    login_as(admin)

    visit uploader_evento_path(evento)

    fill_in 'evento_nova_pasta_show', with: 'Pasta Endereco Fixo'
    attach_file 'Imagem(ns)', Rails.root.join('spec/fixtures/files/sample2.jpg')
    click_button 'Enviar imagem'

    expect(page).to have_content('Evento atualizado com sucesso.')

    evento.reload
    expect(evento.data).to eq(Date.new(2024, 12, 25))
    expect(evento.cidade).to eq('Campinas')
    expect(evento.local).to eq('Rua A')
    expect(evento.imagens.count).to eq(1)
    expect(evento.imagens.first.pasta).to eq('Pasta Endereco Fixo')
  end

  scenario 'admin faz upload de mais de uma imagem no show em um unico envio' do
    admin = create(:user, :uploader)
    evento = create(:evento, nome: 'Evento Upload Multiplo', categoria: :direita, cidade: 'Nao informada', local: 'Nao informado')

    allow(ImagemMetadataExtractor).to receive(:extract).and_return(
      normalized: {
        data_hora: Time.zone.parse('2025-09-07 11:30:00'),
        cidade: 'Sao Paulo',
        local: 'Avenida Paulista',
        gps_location: '-23.550520,-46.633308'
      },
      exif: { 'datetimeoriginal' => '2025:09:07 11:30:00' },
      xmp: {}
    )

    login_as(admin)

    visit uploader_evento_path(evento)

    fill_in 'evento_nova_pasta_show', with: 'Pasta Multipla Show'
    attach_file 'Imagem(ns)', [
      Rails.root.join('spec/fixtures/files/sample.jpg'),
      Rails.root.join('spec/fixtures/files/sample2.jpg')
    ]
    click_button 'Enviar imagem'

    expect(page).to have_content('Evento atualizado com sucesso.')

    evento.reload
    nomes_arquivos = evento.imagens.order(:id).map { |imagem| imagem.arquivo.filename.to_s }

    expect(evento.imagens.count).to eq(2)
    expect(nomes_arquivos).to include('sample.jpg', 'sample2.jpg')
    expect(evento.imagens.pluck(:pasta).uniq).to eq(['Pasta Multipla Show'])
  end

  scenario 'admin faz upload dentro da pasta colapsavel e associa na pasta correspondente' do
    admin = create(:user, :uploader)
    evento = create(:evento, nome: 'Evento Pasta Existente')
    create(:imagem, evento: evento, pasta: 'Pasta A')

    allow(ImagemMetadataExtractor).to receive(:extract).and_return(
      normalized: {
        data_hora: Time.zone.parse('2025-09-07 11:30:00'),
        cidade: 'Sao Paulo',
        local: 'Avenida Paulista',
        gps_location: '-23.550520,-46.633308'
      },
      exif: { 'datetimeoriginal' => '2025:09:07 11:30:00' },
      xmp: {}
    )

    login_as(admin)

    visit pasta_uploader_evento_path(evento, pasta: 'Pasta A')

    attach_file 'Imagem(ns) para Pasta A', Rails.root.join('spec/fixtures/files/sample2.jpg')
    click_button 'Enviar'

    expect(page).to have_content('Evento atualizado com sucesso.')

    imagem = evento.imagens.order(:id).last
    expect(imagem.pasta).to eq('Pasta A')
  end

  scenario 'admin digita nova pasta no upload do show do evento' do
    admin = create(:user, :uploader)
    evento = create(:evento, nome: 'Evento Pasta Nova no Show')

    allow(ImagemMetadataExtractor).to receive(:extract).and_return(
      normalized: {
        data_hora: Time.zone.parse('2025-09-07 11:30:00'),
        cidade: 'Sao Paulo',
        local: 'Avenida Paulista',
        gps_location: '-23.550520,-46.633308'
      },
      exif: { 'datetimeoriginal' => '2025:09:07 11:30:00' },
      xmp: {}
    )

    login_as(admin)

    visit uploader_evento_path(evento)

    fill_in 'evento_nova_pasta_show', with: 'Pasta Nova Upload'
    attach_file 'Imagem(ns)', Rails.root.join('spec/fixtures/files/sample2.jpg')
    click_button 'Enviar imagem'

    expect(page).to have_content('Evento atualizado com sucesso.')

    imagem = evento.imagens.order(:id).last
    expect(imagem.pasta).to eq('Pasta Nova Upload')
  end

  scenario 'admin ordena imagens associadas por ID e por data/hora no show do evento' do
    admin = create(:user, :uploader)
    evento = create(:evento, nome: 'Evento Ordenacao')

    imagem_antiga = create(:imagem, evento: evento, pasta: 'Pasta Ordenacao', data_hora: Time.zone.parse('2024-01-01 10:00:00'))
    imagem_recente = create(:imagem, evento: evento, pasta: 'Pasta Ordenacao', data_hora: Time.zone.parse('2024-01-03 10:00:00'))

    login_as(admin)

    visit pasta_uploader_evento_path(evento, pasta: 'Pasta Ordenacao', sort: 'id', direction: 'asc')
    ids_por_id_asc = page.all('table tbody tr td:first-child').map { |cell| cell.text.to_i }
    expect(ids_por_id_asc).to eq(ids_por_id_asc.sort)

    visit pasta_uploader_evento_path(evento, pasta: 'Pasta Ordenacao', sort: 'data_hora', direction: 'asc')
    ids_por_data_asc = page.all('table tbody tr td:first-child').map { |cell| cell.text.to_i }
    expect(ids_por_data_asc.first).to eq(imagem_antiga.id)
    expect(ids_por_data_asc.last).to eq(imagem_recente.id)
  end

  scenario 'admin visualiza imagens agrupadas por pasta no show do evento' do
    admin = create(:user, :uploader)
    evento = create(:evento, nome: 'Evento Pastas')

    create(:imagem, evento: evento, pasta: 'Pasta A')
    create(:imagem, evento: evento, pasta: 'Pasta A')
    create(:imagem, evento: evento, pasta: 'Pasta B')
    create(:imagem, evento: evento, pasta: nil)

    login_as(admin)

    visit uploader_evento_path(evento)

    expect(page).to have_link('Pasta A')
    expect(page).to have_link('Pasta B')
    expect(page).to have_link('Sem pasta')

    within('tr', text: 'Pasta A') do
      expect(page).to have_content('2')
    end
  end

  scenario 'admin deleta imagem na tabela do evento e permanece na pagina do evento' do
    admin = create(:user, :uploader)
    evento = create(:evento, nome: 'Evento Delecao')
    imagem = create(:imagem, evento: evento, pasta: 'Pasta A')

    login_as(admin)

    visit pasta_uploader_evento_path(evento, pasta: 'Pasta A')

    within('table tbody tr', text: imagem.id.to_s) do
      click_button 'Deletar'
    end

    expect(page).to have_current_path(pasta_uploader_evento_path(evento, pasta: 'Pasta A'))
    expect(page).to have_content('Imagem removida com sucesso!')
    expect(Imagem.exists?(imagem.id)).to be(false)
  end

  scenario 'admin visualiza categoria decorada no index com o mesmo padrao do show' do
    admin = create(:user, :uploader)
    evento_direita = create(:evento, nome: 'Evento Direita', categoria: :direita)
    evento_esquerda = create(:evento, nome: 'Evento Esquerda', categoria: :esquerda)
    evento_sem_categoria = create(:evento, nome: 'Evento Sem Categoria', categoria: nil)

    login_as(admin)

    visit uploader_eventos_path

    expect(page).to have_selector(
      "#evento-#{evento_direita.id} .evento-categoria-badge.evento-categoria-direita",
      text: 'Direita'
    )

    expect(page).to have_selector(
      "#evento-#{evento_esquerda.id} .evento-categoria-badge.btn-danger",
      text: 'Esquerda'
    )

    expect(page).to have_selector(
      "#evento-#{evento_sem_categoria.id} .evento-categoria-badge.btn-outline-secondary",
      text: 'Sem categoria'
    )
  end

  scenario 'admin filtra por cidade e categoria e ordena por data no index' do
    admin = create(:user, :uploader)
    cidade_teste = 'Cidade Filtro Ordenacao'
    evento_data_antiga = create(:evento, nome: 'Evento Data Antiga', categoria: :direita, cidade: cidade_teste, data: Date.new(2024, 1, 1))
    evento_outra_cidade = create(:evento, nome: 'Evento Campinas', categoria: :direita, cidade: 'Campinas', data: Date.new(2024, 2, 1))
    evento_data_recente = create(:evento, nome: 'Evento Data Recente', categoria: :esquerda, cidade: cidade_teste, data: Date.new(2024, 3, 1))

    login_as(admin)

    visit uploader_eventos_path(cidade: cidade_teste, categoria: 'direita')

    expect(page).to have_selector("#evento-#{evento_data_antiga.id}")
    expect(page).not_to have_selector("#evento-#{evento_outra_cidade.id}")
    expect(page).not_to have_selector("#evento-#{evento_data_recente.id}")

    visit uploader_eventos_path(cidade: cidade_teste, sort: 'data', direction: 'asc')
    nomes_asc = page.all('table tbody tr td:first-child a').map(&:text)
    expect(nomes_asc.first).to eq(evento_data_antiga.nome)
    expect(nomes_asc.last).to eq(evento_data_recente.nome)

    visit uploader_eventos_path(cidade: cidade_teste, sort: 'data', direction: 'desc')
    nomes_desc = page.all('table tbody tr td:first-child a').map(&:text)
    expect(nomes_desc.first).to eq(evento_data_recente.nome)
    expect(nomes_desc.last).to eq(evento_data_antiga.nome)
  end

  scenario 'annotator nao acessa CRUD de eventos' do
    annotator = create(:user, :annotator)

    login_as(annotator)

    visit uploader_eventos_path

    expect(page).to have_content('Permissão negada')
    expect(page).to have_current_path(dashboard_path)
  end
end
