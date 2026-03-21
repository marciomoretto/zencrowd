require 'rails_helper'

RSpec.describe 'Annotator reserva imagem e vê tarefa', type: :feature do
  let!(:admin) { create(:user, :admin) }
  let!(:annotator) { create(:user, :annotator) }
  let!(:image) { create(:image, uploader: admin, status: :available, original_filename: 'imagem1.png', task_value: 5.0) }

  scenario 'Annotator faz login, reserva imagem e vê sua tarefa' do
    visit '/login'
    fill_in 'E-mail', with: annotator.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'

    click_link 'Tarefas Disponíveis', match: :first
    expect(page).to have_content('Tarefas Disponíveis')
    expect(page).to have_link('imagem1.png', href: tile_path(image))
    expect(page).to have_content('R$5,00')
    within("#tile-row-#{image.id}") do
      click_button 'Reservar'
    end

    expect(page).to have_selector('.alert.alert-success', text: 'Tile reservado com sucesso!')
    expect(page).to have_selector('.alert.alert-warning', text: 'Tarefas ociosas por 48 horas ficam abandonadas e retornam para a fila disponível.')
    expect(page).to have_content('Tarefa Atual')
    expect(page).to have_content('Editor de Pontos (ZenPlot)')
    expect(page).to have_css('[data-wpd-app]')
  end

  scenario 'Annotator ordena tarefas disponíveis por valor da tarefa' do
    menor_valor = create(:image, uploader: admin, status: :available, original_filename: 'valor_baixo.png', task_value: 1.0)
    maior_valor = create(:image, uploader: admin, status: :available, original_filename: 'valor_alto.png', task_value: 9.0)

    visit '/login'
    fill_in 'E-mail', with: annotator.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'

    click_link 'Tarefas Disponíveis', match: :first

    click_link 'Valor da Tarefa'
    arquivos_ordenados = all('table tbody tr td:nth-child(2)').map(&:text)
    expect(arquivos_ordenados.index(menor_valor.original_filename)).to be < arquivos_ordenados.index(maior_valor.original_filename)

    click_link 'Valor da Tarefa'
    arquivos_ordenados = all('table tbody tr td:nth-child(2)').map(&:text)
    expect(arquivos_ordenados.index(maior_valor.original_filename)).to be < arquivos_ordenados.index(menor_valor.original_filename)
  end

  scenario 'Annotator acessa o show do tile pela tabela de disponíveis' do
    visit '/login'
    fill_in 'E-mail', with: annotator.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'

    click_link 'Tarefas Disponíveis', match: :first
    click_link 'imagem1.png'

    expect(page).to have_current_path(tile_path(image))
    expect(page).to have_content("Tile #{image.id}")
    expect(page).to have_content('ID')
    expect(page).to have_content('Arquivo')
    expect(page).to have_content('Valor da tarefa')
    expect(page).to have_content('R$ 5,00')
    expect(page).not_to have_button('Salvar')
    expect(page).not_to have_button('Contar cabeças')
    expect(page).not_to have_button('Remover')
    expect(page).not_to have_selector("#task-value-display-#{image.id}")
  end

  scenario 'Annotator visualiza coluna Situação na tabela de disponíveis' do
    tarefa_nova = create(:tile, uploader: admin, status: :available, original_filename: 'nova.png', task_value: 4.0)
    tarefa_iniciada = create(:tile, uploader: admin, status: :abandoned, original_filename: 'iniciada.png', task_value: 6.0)
    create(:tile_point_set, tile: tarefa_iniciada, points: [{ id: 1, x: 12.0, y: 14.0 }])

    visit '/login'
    fill_in 'E-mail', with: annotator.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'

    click_link 'Tarefas Disponíveis', match: :first
    expect(page).to have_content('Situação')

    within("#tile-row-#{tarefa_nova.id}") do
      expect(page).to have_content('Nova')
    end

    within("#tile-row-#{tarefa_iniciada.id}") do
      expect(page).to have_content('Abandonada')
    end
  end

  scenario 'Annotator filtra tarefas disponíveis por situação' do
    tarefa_nova = create(:tile, uploader: admin, status: :available, original_filename: 'nova_ordenacao.png', task_value: 4.0)
    tarefa_iniciada = create(:tile, uploader: admin, status: :abandoned, original_filename: 'iniciada_ordenacao.png', task_value: 6.0)
    create(:tile_point_set, tile: tarefa_iniciada, points: [{ id: 1, x: 12.0, y: 14.0 }])

    visit '/login'
    fill_in 'E-mail', with: annotator.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'

    click_link 'Tarefas Disponíveis', match: :first

    select 'Abandonada', from: 'Filtrar por status'
    click_button 'Aplicar filtro'

    expect(page).to have_content(tarefa_iniciada.original_filename)
    expect(page).not_to have_content(tarefa_nova.original_filename)
  end
end
