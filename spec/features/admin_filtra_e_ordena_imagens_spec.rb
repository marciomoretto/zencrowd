require 'rails_helper'

RSpec.describe 'Admin filtra e ordena imagens', type: :feature do
  let!(:admin) { create(:user, :admin) }

  def login_as_admin
    visit login_path
    fill_in 'E-mail', with: admin.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'
  end

  def click_sort(label)
    within('table thead') do
      first('a', text: /\A#{Regexp.escape(label)}\z/).click
    end
  end

  def first_row_id
    first('table tbody tr td:nth-child(1)').text.to_i
  end

  scenario 'admin filtra imagens por cidade' do
    create(:imagem, cidade: 'Cidade Alfa', local: 'Local Alfa')
    create(:imagem, cidade: 'Cidade Beta', local: 'Local Beta')

    login_as_admin
    visit imagens_path

    select 'Cidade Alfa', from: 'Cidade'
    click_button 'Aplicar filtro'

    expect(page).to have_content('Local Alfa')
    expect(page).not_to have_content('Local Beta')
  end

  scenario 'admin ordena por ID e data/hora' do
    imagem_antiga = create(:imagem, cidade: 'Cidade Ordenacao', data_hora: Time.zone.parse('2024-01-01 10:00:00'))
    create(:imagem, cidade: 'Cidade Ordenacao', data_hora: Time.zone.parse('2024-01-02 10:00:00'))
    imagem_recente = create(:imagem, cidade: 'Cidade Ordenacao', data_hora: Time.zone.parse('2024-01-03 10:00:00'))

    login_as_admin
    visit imagens_path

    select 'Cidade Ordenacao', from: 'Cidade'
    click_button 'Aplicar filtro'

    click_sort('ID')
    expect(first_row_id).to eq(imagem_antiga.id)

    click_sort('ID')
    expect(first_row_id).to eq(imagem_recente.id)

    click_sort('Data e Hora')
    expect(first_row_id).to eq(imagem_antiga.id)

    click_sort('Data e Hora')
    expect(first_row_id).to eq(imagem_recente.id)
  end

  scenario 'admin visualiza data/hora vinda do campo data_hora do model' do
    imagem = create(
      :imagem,
      cidade: 'Cidade Metadata',
      data_hora: Time.zone.parse('2030-01-01 10:00:00'),
      exif_metadata: { 'date_time_original' => '2024:01:05 12:34:56' },
      xmp_metadata: {}
    )

    login_as_admin
    visit imagens_path

    select 'Cidade Metadata', from: 'Cidade'
    click_button 'Aplicar filtro'

    origem_exif = I18n.l(Time.zone.parse('2024-01-05 12:34:56'), format: :short)
    cadastro = I18n.l(Time.zone.parse('2030-01-01 10:00:00'), format: :short)

    expect(page).to have_content(imagem.id.to_s)
    expect(page).to have_content(cadastro)
    expect(page).not_to have_content(origem_exif)
  end

  scenario 'admin visualiza coluna Pasta no index' do
    create(:imagem, cidade: 'Cidade Pasta', pasta: 'Pasta Centro')

    login_as_admin
    visit imagens_path

    select 'Cidade Pasta', from: 'Cidade'
    click_button 'Aplicar filtro'

    within('table thead') do
      expect(page).to have_content('Pasta')
    end

    expect(page).to have_content('Pasta Centro')
  end
end
