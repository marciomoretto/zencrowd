require 'rails_helper'

RSpec.describe 'Admin filtra e ordena tiles', type: :feature do
  let!(:admin) { create(:user, :admin) }

  prepend_before do
    Review.delete_all
    AnnotationPoint.delete_all
    Annotation.delete_all
    Assignment.delete_all
    Tile.delete_all
  end

  def login_as(user)
    visit login_path
    fill_in 'E-mail', with: user.email
    fill_in 'Senha', with: 'password123'
    click_button 'Entrar'
  end

  def click_sort(label)
    within('table thead') do
      first('a', text: /\A#{Regexp.escape(label)}\z/).click
    end
  end

  def expect_filenames_in_order(*filenames)
    positions = filenames.map do |filename|
      expect(page).to have_content(filename)
      page.body.index(filename)
    end

    expect(positions).to eq(positions.sort)
  end

  scenario 'admin filtra por status e reservada por' do
    annotator_a = create(:user, :annotator, name: 'Annotator A')
    annotator_b = create(:user, :annotator, name: 'Annotator B')

    create(:tile,
           original_filename: 'tile_alvo.jpg',
           status: :reserved,
           reserver: annotator_a,
           reserved_at: Time.current,
           uploader: admin)
    create(:tile,
           original_filename: 'tile_outro_reservado.jpg',
           status: :reserved,
           reserver: annotator_b,
           reserved_at: Time.current,
           uploader: admin)
    create(:tile,
           original_filename: 'tile_disponivel.jpg',
           status: :available,
           uploader: admin)

    login_as(admin)
    visit tiles_path

    select 'Reservada', from: 'Status'
    select 'Annotator A', from: 'Reservada por'
    click_button 'Aplicar filtros'

    expect(page).to have_content('tile_alvo.jpg')
    expect(page).not_to have_content('tile_outro_reservado.jpg')
    expect(page).not_to have_content('tile_disponivel.jpg')
  end

  scenario 'admin ordena por ID, valor e data de criação' do
    create(:tile,
           original_filename: 'tile_old.jpg',
           task_value: 30.0,
           created_at: Time.zone.parse('2024-01-01 10:00:00'),
           uploader: admin)
    create(:tile,
           original_filename: 'tile_mid.jpg',
           task_value: 10.0,
           created_at: Time.zone.parse('2024-01-02 10:00:00'),
           uploader: admin)
    create(:tile,
           original_filename: 'tile_new.jpg',
           task_value: 20.0,
           created_at: Time.zone.parse('2024-01-03 10:00:00'),
           uploader: admin)

    login_as(admin)
    visit tiles_path

    click_sort('ID')
    expect_filenames_in_order('tile_old.jpg', 'tile_mid.jpg', 'tile_new.jpg')

    click_sort('ID')
    expect_filenames_in_order('tile_new.jpg', 'tile_mid.jpg', 'tile_old.jpg')

    click_sort('Valor da Tarefa')
    expect_filenames_in_order('tile_mid.jpg', 'tile_new.jpg', 'tile_old.jpg')

    click_sort('Valor da Tarefa')
    expect_filenames_in_order('tile_old.jpg', 'tile_new.jpg', 'tile_mid.jpg')

    click_sort('Criada em')
    expect_filenames_in_order('tile_old.jpg', 'tile_mid.jpg', 'tile_new.jpg')

    click_sort('Criada em')
    expect_filenames_in_order('tile_new.jpg', 'tile_mid.jpg', 'tile_old.jpg')
  end
end
