require 'rails_helper'

RSpec.describe 'Reviewer users', type: :request do
  let(:reviewer) { create(:user, :reviewer) }
  let(:annotator) { create(:user, :annotator, name: 'Pessoa Privada', email: 'privado@example.com') }
  let(:other) { create(:user, :annotator, name: 'Outro Anotador') }

  def login_as(user)
    post login_path, params: { email: user.email, password: 'password123' }
  end

  def tile_with_annotation(user, status, filename, **attributes)
    tile = create(:tile, status: status, original_filename: filename, **attributes)
    create(:annotation, image: tile, user: user)
    tile
  end

  it 'lists users by name only, with escaped names and pagination' do
    create(:user, name: '<Nome> Particular', email: 'secreto@example.com')
    create(:user, name: 'Z Pessoa')
    create(:user, name: 'A Pessoa')
    login_as(reviewer)

    get reviewer_users_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('&lt;Nome&gt; Particular')
    expect(response.body).not_to include('secreto@example.com')
    names = Nokogiri::HTML(response.body).css('table tbody tr').map(&:text)
    expect(names.index('A Pessoa')).to be < names.index('Z Pessoa')
    get reviewer_users_path(per: 1, page: 1)
    expect(Nokogiri::HTML(response.body).css('table tbody tr').size).to eq(1)
    expect(response.body).to include('page=2')
  end

  it 'shows only pending tiles belonging to the current annotation without personal details' do
    first = tile_with_annotation(annotator, :submitted, 'primeira.jpg', reserver: other)
    second = tile_with_annotation(annotator, :in_review, 'segunda.jpg')
    %i[reserved approved rejected paid].each do |status|
      tile_with_annotation(annotator, status, "#{status}.jpg")
    end
    tile_with_annotation(other, :in_review, 'outra.jpg')
    reassigned = tile_with_annotation(annotator, :in_review, 'reenviada.jpg')
    create(:annotation, image: reassigned, user: other)
    from_other = tile_with_annotation(other, :in_review, 'nova.jpg')
    create(:annotation, image: from_other, user: annotator)
    login_as(reviewer)

    get reviewer_user_path(annotator)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('primeira.jpg', 'segunda.jpg', 'nova.jpg')
    expect(response.body).not_to include('reserved.jpg', 'approved.jpg', 'rejected.jpg', 'paid.jpg', 'outra.jpg', 'reenviada.jpg')
    expect(response.body).not_to include(annotator.name, annotator.email, other.name)
    expect(response.body).not_to include('<th>Anotador</th>')
    expect(response.body).to include(reviewer_review_path(first), reviewer_review_path(second))
  end

  it 'breaks equal annotation timestamps by id and does not duplicate tiles' do
    tile = tile_with_annotation(other, :in_review, 'empate.jpg')
    time = Time.current
    tile.annotations.update_all(created_at: time)
    create(:annotation, image: tile, user: annotator, created_at: time)
    login_as(reviewer)

    get reviewer_user_path(annotator)
    expect(response.body.scan('empate.jpg').size).to eq(1)
    get reviewer_user_path(other)
    expect(response.body).not_to include('empate.jpg')
  end

  it 'supports sorting, pagination, and an empty list' do
    tile_with_annotation(annotator, :in_review, 'dez.jpg', head_count: 10)
    tile_with_annotation(annotator, :submitted, 'cinco.jpg', head_count: 5)
    login_as(reviewer)
    get reviewer_user_path(annotator, sort: 'estimated_count', direction: 'asc', per: 1)
    expect(response.body).to include('cinco.jpg')
    expect(response.body).not_to include('dez.jpg')
    expect(response.body).to include("page=2", reviewer_user_path(annotator))
    get reviewer_user_path(annotator, sort: 'estimated_count', direction: 'desc', per: 1)
    expect(response.body).to include('dez.jpg')
    get reviewer_user_path(other)
    expect(response.body).to include('Nenhum tile para revisar.')
  end

  it 'requires authentication and reviewer authorization' do
    get reviewer_users_path
    expect(response).to redirect_to(login_path)
    login_as(annotator)
    get reviewer_users_path
    expect(response).to redirect_to(root_path)
    get reviewer_user_path(other)
    expect(response).to redirect_to(root_path)
  end

  it 'preserves filters and sorting on the general review list' do
    tile_with_annotation(annotator, :submitted, 'primeira.jpg', reserver: annotator, head_count: 10)
    tile_with_annotation(annotator, :submitted, 'segunda.jpg', reserver: annotator, head_count: 5)
    tile_with_annotation(other, :in_review, 'outra.jpg', reserver: other)
    login_as(reviewer)

    get reviewer_reviews_path(status: 'submitted', annotator_id: annotator.id, sort: 'estimated_count', direction: 'asc')
    rows = Nokogiri::HTML(response.body).css('table tbody tr').map(&:text)
    expect(rows.size).to eq(2)
    expect(rows.first).to include('segunda.jpg')
    expect(rows.last).to include('primeira.jpg')
    expect(response.body).to include('<th>Anotador</th>', annotator.name)
    expect(response.body).not_to include('outra.jpg')
  end

  it 'links each displayed annotator to their pending review tasks, leaving unassigned tiles without a link' do
    tile_with_annotation(annotator, :submitted, 'primeira.jpg', reserver: annotator)
    tile_with_annotation(other, :in_review, 'outra.jpg', reserver: other)
    tile_with_annotation(other, :in_review, 'sem-reserva.jpg')
    login_as(reviewer)

    get reviewer_reviews_path
    rows = Nokogiri::HTML(response.body).css('table tbody tr')
    row = rows.find { |item| item.text.include?('primeira.jpg') }
    link = row.css('td').last.at_css('a')
    expect(link.text).to eq(annotator.name)
    expect(link['href']).to eq(reviewer_user_path(annotator))
    unassigned = rows.find { |item| item.text.include?('sem-reserva.jpg') }
    expect(unassigned.css('td').last.text.strip).to eq('-')
    expect(unassigned.css('td').last.at_css('a')).to be_nil

    get link['href']
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('primeira.jpg')
    expect(response.body).not_to include('outra.jpg', 'sem-reserva.jpg', annotator.name)
  end
end
