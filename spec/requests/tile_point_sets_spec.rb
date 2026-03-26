require 'rails_helper'

RSpec.describe 'Tile point sets', type: :request do
  let!(:admin) { create(:user, :admin) }
  let!(:annotator) { create(:user, :annotator) }
  let!(:other_annotator) { create(:user, :annotator) }
  let!(:tile) do
    create(:tile, uploader: admin, status: :reserved, reserver: annotator, reserved_at: Time.current)
  end

  before do
    TilePointSet.delete_all
  end

  def login_as(user)
    delete '/logout'

    post '/login', params: { email: user.email, password: 'password123' }
    session_cookie_key = response.cookies.key?('_zencrowd_session') ? '_zencrowd_session' : 'session'
    if response.cookies[session_cookie_key]
      cookies[session_cookie_key] = response.cookies[session_cookie_key]
    end
  end

  describe 'GET /tiles/:id/zen_plot_points' do
    context 'when there are no persisted points' do
      it 'returns an empty points payload' do
        login_as(annotator)

        get "/tiles/#{tile.id}/zen_plot_points", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['axis']).to eq('image')
        expect(json['points']).to eq([])
      end
    end

    context 'when there are persisted points for tile' do
      before do
        create(:tile_point_set, tile: tile, points: [{ id: 1, x: 11.25, y: 19.75 }])
      end

      it 'returns persisted points' do
        login_as(annotator)

        get "/tiles/#{tile.id}/zen_plot_points", headers: { 'ACCEPT' => 'application/json' }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['axis']).to eq('image')
        expect(json['points']).to eq([{ 'id' => 1, 'x' => 11.25, 'y' => 19.75 }])
      end
    end

    it 'forbids access for annotator that is not reserver' do
      login_as(other_annotator)

      get "/tiles/#{tile.id}/zen_plot_points", headers: { 'ACCEPT' => 'application/json' }

      expect(response).to have_http_status(:forbidden)
      json = JSON.parse(response.body)
      expect(json['error']).to eq('Permissão negada para acessar os pontos deste tile')
    end
  end

  describe 'POST /tiles/:id/zen_plot_points' do
    let(:payload) do
      {
        axis: 'image',
        points: [
          { id: 7, x: 15.129, y: 20.556 },
          { x: 30, y: 40.4 }
        ]
      }
    end

    it 'creates a tile point set for reserver annotator' do
      login_as(annotator)

      expect do
        post "/tiles/#{tile.id}/zen_plot_points",
             params: payload.to_json,
             headers: { 'ACCEPT' => 'application/json', 'CONTENT_TYPE' => 'application/json' }
      end.to change(TilePointSet, :count).by(1)

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json['tile_id']).to eq(tile.id)
      expect(json['points_count']).to eq(2)
      expect(json['finalized']).to eq(false)
      expect(json['points']).to eq([
        { 'id' => 7, 'x' => 15.13, 'y' => 20.56 },
        { 'id' => 2, 'x' => 30.0, 'y' => 40.4 }
      ])
    end

    it 'updates the existing tile point set' do
      create(:tile_point_set, tile: tile, points: [{ id: 1, x: 1.0, y: 1.0 }])
      login_as(annotator)

      expect do
        post "/tiles/#{tile.id}/zen_plot_points",
             params: payload.to_json,
             headers: { 'ACCEPT' => 'application/json', 'CONTENT_TYPE' => 'application/json' }
      end.not_to change(TilePointSet, :count)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['finalized']).to eq(false)
      expect(tile.reload.tile_point_set.points).to eq([
        { 'id' => 7, 'x' => 15.13, 'y' => 20.56 },
        { 'id' => 2, 'x' => 30.0, 'y' => 40.4 }
      ])
    end

    it 'refreshes reservation expiration and returns warning when saving points' do
      create(:tile_point_set, tile: tile, points: [{ id: 1, x: 1.0, y: 1.0 }])
      tile.update!(reservation_expires_at: 30.minutes.from_now)
      old_expiration = tile.reservation_expires_at
      login_as(annotator)

      post "/tiles/#{tile.id}/zen_plot_points",
           params: payload.to_json,
           headers: { 'ACCEPT' => 'application/json', 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['warning']).to include('Tempo de expiração da tarefa foi atualizado')
      expect(json['reservation_expires_at']).to be_present
      expect(tile.reload.reservation_expires_at).to be > old_expiration
    end

    it 'returns validation error for invalid points payload' do
      login_as(annotator)

      post "/tiles/#{tile.id}/zen_plot_points",
           params: { axis: 'image', points: [{ x: -1, y: 10 }] }.to_json,
           headers: { 'ACCEPT' => 'application/json', 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json['errors']).to be_an(Array)
      expect(json['errors'].first).to include('coordenada x negativa')
    end

    it 'forbids access for annotator that is not reserver' do
      login_as(other_annotator)

      post "/tiles/#{tile.id}/zen_plot_points",
           params: payload.to_json,
           headers: { 'ACCEPT' => 'application/json', 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:forbidden)
      json = JSON.parse(response.body)
      expect(json['error']).to eq('Permissão negada para acessar os pontos deste tile')
    end
  end

  describe 'POST /tiles/:id/finalize_zen_plot_points' do
    let(:payload) do
      {
        axis: 'image',
        points: [
          { id: 3, x: 88.995, y: 144.501 },
          { x: 31.2, y: 10.7 }
        ]
      }
    end

    it 'creates and finalizes a tile point set for reserver annotator' do
      login_as(annotator)

      expect do
        post "/tiles/#{tile.id}/finalize_zen_plot_points",
             params: payload.to_json,
             headers: { 'ACCEPT' => 'application/json', 'CONTENT_TYPE' => 'application/json' }
      end.to change(TilePointSet, :count).by(1)
        .and change(Annotation, :count).by(1)

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)

      expect(json['tile_id']).to eq(tile.id)
      expect(json['finalized']).to eq(true)
      expect(json['finalized_at']).to be_present
      expect(json['points']).to eq([
        { 'id' => 3, 'x' => 89.0, 'y' => 144.5 },
        { 'id' => 2, 'x' => 31.2, 'y' => 10.7 }
      ])

      point_set = tile.reload.tile_point_set
      expect(point_set).to be_present
      expect(point_set.finalized_at).to be_present
      expect(tile.status).to eq('in_review')

      latest_annotation = tile.annotations.order(created_at: :desc).first
      expect(latest_annotation).to be_present
      expect(latest_annotation.user_id).to eq(annotator.id)
      expect(latest_annotation.annotation_points.count).to eq(2)
    end

    it 'updates and finalizes an existing tile point set' do
      create(:tile_point_set, tile: tile, points: [{ id: 1, x: 1.0, y: 1.0 }], finalized_at: nil)
      login_as(annotator)

      expect do
        post "/tiles/#{tile.id}/finalize_zen_plot_points",
             params: payload.to_json,
             headers: { 'ACCEPT' => 'application/json', 'CONTENT_TYPE' => 'application/json' }
      end.to change(Annotation, :count).by(1)

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['finalized']).to eq(true)

      point_set = tile.reload.tile_point_set
      expect(point_set.points).to eq([
        { 'id' => 3, 'x' => 89.0, 'y' => 144.5 },
        { 'id' => 2, 'x' => 31.2, 'y' => 10.7 }
      ])
      expect(point_set.finalized_at).to be_present
      expect(tile.status).to eq('in_review')
    end

    it 'returns validation error for invalid points payload' do
      login_as(annotator)

      post "/tiles/#{tile.id}/finalize_zen_plot_points",
           params: { axis: 'image', points: [{ x: -2, y: 10 }] }.to_json,
           headers: { 'ACCEPT' => 'application/json', 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json['errors']).to be_an(Array)
      expect(json['errors'].first).to include('coordenada x negativa')
    end

    it 'forbids access for annotator that is not reserver' do
      login_as(other_annotator)

      post "/tiles/#{tile.id}/finalize_zen_plot_points",
           params: payload.to_json,
           headers: { 'ACCEPT' => 'application/json', 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:forbidden)
      json = JSON.parse(response.body)
      expect(json['error']).to eq('Permissão negada para acessar os pontos deste tile')
    end
  end
end
