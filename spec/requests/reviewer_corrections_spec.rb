require 'rails_helper'

RSpec.describe 'Reviewer corrections', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:annotator) { create(:user, :annotator) }
  let(:reviewer) { create(:user, :reviewer) }
  let(:other_reviewer) { create(:user, :reviewer) }
  let!(:tile) { create(:tile, uploader: admin, reserver: annotator, status: :in_review) }
  let!(:annotation) { create(:annotation, image: tile, user: annotator, submitted_at: Time.current) }
  let!(:point_set) do
    create(:tile_point_set, tile: tile, finalized_at: Time.current,
           points: [{ id: 1, x: 10, y: 20 }, { id: 2, x: 30, y: 40 }])
  end
  let(:headers) { { 'ACCEPT' => 'application/json', 'CONTENT_TYPE' => 'application/json' } }

  def login_as(user)
    delete logout_path
    post login_path, params: { email: user.email, password: 'password123' }
  end

  def save_points(points, version: nil)
    post points_reviewer_review_path(tile, format: :json),
         params: { points: points, version: version }.to_json, headers: headers
  end

  it 'enables the alternate mouse action only while the reviewer can edit' do
    tile.update!(storage_path: Rails.root.join('spec/fixtures/files/test_image.jpg'))
    login_as(reviewer)
    get reviewer_review_path(tile)
    expect(response.body).to include('contextmenu-&gt;alternate-point#handle').or include('contextmenu->alternate-point#handle')
    post approve_tile_path(tile), headers: { 'ACCEPT' => 'application/json' }
    get reviewer_review_path(tile)
    expect(response.body).not_to include('contextmenu->alternate-point#handle')
    expect(response.body).not_to include('contextmenu-&gt;alternate-point#handle')
  end

  it 'associates the optional message field only with the rejection form' do
    tile.update!(storage_path: Rails.root.join('spec/fixtures/files/test_image.jpg'))
    login_as(reviewer)
    get reviewer_review_path(tile)
    html = Nokogiri::HTML(response.body)
    field = html.at_css('textarea#review_message')
    expect(field['name']).to eq('message')
    expect(field['form']).to eq('review-reject-form')
    expect(field['maxlength']).to eq(Review::MESSAGE_MAX_LENGTH.to_s)
    expect(html.at_css('form#review-reject-form')['action']).to eq(reject_tile_path(tile))
  end

  it 'saves net additions and removals, retains originals and exports a combined payload' do
    annotation.annotation_points.create!(x: 10, y: 20)
    annotation.annotation_points.create!(x: 30, y: 40)
    login_as(reviewer)
    save_points([{ x: 30, y: 40, source_id: 2 }, { x: 50.5, y: 60, source_id: nil }])

    expect(response).to have_http_status(:ok)
    correction = annotation.reload.review_correction
    expect([correction.added_count, correction.removed_count]).to eq([1, 1])
    expect(correction.original_points.size).to eq(2)
    expect(correction.reviewer).to eq(reviewer)
    expect(annotation.annotation_points.order(:id).pluck(:x, :y)).to eq([[10, 20], [30, 40]])
    expect(tile.reload.tile_point_set.points).to eq([
      { 'id' => 1, 'x' => 30.0, 'y' => 40.0 },
      { 'id' => 2, 'x' => 50.5, 'y' => 60.0 }
    ])

    get zen_plot_points_tile_path(tile, format: :json)
    expect(JSON.parse(response.body)['points']).to eq(tile.tile_point_set.points)

    save_points([{ x: 10, y: 20, source_id: 1 }, { x: 30, y: 40, source_id: 2 }],
                version: correction.lock_version)
    expect(response).to have_http_status(:ok)
    expect([correction.reload.added_count, correction.removed_count]).to eq([0, 0])
  end

  it 'claims a submission before editing and prevents another reviewer from claiming it' do
    login_as(reviewer)
    post claim_reviewer_review_path(tile, format: :json), headers: headers
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)['points']).to eq([
      { 'x' => 10.0, 'y' => 20.0, 'source_id' => 1 },
      { 'x' => 30.0, 'y' => 40.0, 'source_id' => 2 }
    ])
    login_as(other_reviewer)
    post claim_reviewer_review_path(tile, format: :json), headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(annotation.reload.review_correction.reviewer).to eq(reviewer)
  end

  it 'does not let the annotator overwrite the submitted points' do
    login_as(annotator)
    post zen_plot_points_tile_path(tile, format: :json),
         params: { points: [] }.to_json, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(tile.reload.tile_point_set.points.size).to eq(2)
  end

  it 'preserves saved corrections on rejection for the annotator' do
    login_as(reviewer)
    save_points([{ x: 50, y: 60, source_id: nil }])
    post reject_tile_path(tile), params: { correction_version: annotation.reload.review_correction.lock_version, message: "Faltou uma cabeça.\nRevise o canto." },
         headers: { 'ACCEPT' => 'application/json' }
    expect(response).to have_http_status(:ok)
    expect(tile.reload).to be_rejected
    expect(tile.tile_point_set.points).to eq([{ 'id' => 1, 'x' => 50.0, 'y' => 60.0 }])
    expect(tile.tile_point_set.finalized_at).to be_nil
    expect(annotation.reload.review.message).to eq("Faltou uma cabeça.\nRevise o canto.")
  end

  it 'shows a rejection message to the annotator on the returned task, escaped as text' do
    login_as(reviewer)
    post reject_tile_path(tile), params: { message: "Revise <script>alert(1)</script>\na região." },
         headers: { 'ACCEPT' => 'application/json' }
    expect(response).to have_http_status(:ok)
    login_as(annotator)
    get my_task_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Mensagem da revisão:', 'Revise &lt;script&gt;alert(1)&lt;/script&gt;', 'a região.')
    expect(tile.reload).to be_reserved
    get my_task_path
    expect(response.body).to include('Mensagem da revisão:')
  end

  it 'does not show a previous annotator message to a different reserver' do
    login_as(reviewer)
    post reject_tile_path(tile), params: { message: 'Mensagem privada do retrabalho' },
         headers: { 'ACCEPT' => 'application/json' }
    other_annotator = create(:user, :annotator)
    tile.update!(status: :reserved, reserver: other_annotator, reserved_at: Time.current)
    login_as(other_annotator)
    get my_task_path
    expect(response.body).not_to include('Mensagem privada do retrabalho')
  end

  it 'rejects oversized or invalid messages without changing the tile' do
    login_as(reviewer)
    post reject_tile_path(tile), params: { message: 'a' * (Review::MESSAGE_MAX_LENGTH + 1) },
         headers: { 'ACCEPT' => 'application/json' }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)['error']).to include('máximo')
    post reject_tile_path(tile), params: { message: { invalid: 'value' } },
         headers: { 'ACCEPT' => 'application/json' }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(tile.reload).to be_in_review
    expect(annotation.reload.review).to be_nil
  end

  it 'allows rejection without a message' do
    login_as(reviewer)
    post reject_tile_path(tile), headers: { 'ACCEPT' => 'application/json' }
    expect(response).to have_http_status(:ok)
    expect(annotation.reload.review.message).to be_nil
  end

  it 'does not show an old message after a later submission' do
    login_as(reviewer)
    post reject_tile_path(tile), params: { message: 'Mensagem antiga' },
         headers: { 'ACCEPT' => 'application/json' }
    expect(response).to have_http_status(:ok)
    create(:annotation, image: tile, user: annotator, submitted_at: Time.current, created_at: 1.second.from_now)
    tile.update!(status: :reserved, reserved_at: Time.current)
    login_as(annotator)
    get my_task_path
    expect(response.body).not_to include('Mensagem antiga')
  end

  it 'prevents another reviewer and stale pages from overwriting or deciding' do
    login_as(reviewer)
    save_points([{ x: 10, y: 20, source_id: 1 }])
    expect(response).to have_http_status(:ok)
    save_points([], version: nil)
    expect(response).to have_http_status(:unprocessable_entity)

    login_as(other_reviewer)
    save_points([], version: 0)
    expect(response).to have_http_status(:unprocessable_entity)
    post approve_tile_path(tile), headers: { 'ACCEPT' => 'application/json' }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(tile.reload).to be_in_review
  end

  it 'does not decide using an outdated correction version' do
    login_as(reviewer)
    save_points([{ x: 10, y: 20, source_id: 1 }])
    save_points([{ x: 30, y: 40, source_id: 2 }], version: 0)
    post approve_tile_path(tile), params: { correction_version: 0 }, headers: { 'ACCEPT' => 'application/json' }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(tile.reload).to be_in_review
    post approve_tile_path(tile), params: { correction_version: 1 }, headers: { 'ACCEPT' => 'application/json' }
    expect(response).to have_http_status(:ok)
    expect(tile.reload).to be_approved
  end

  it 'exports corrected points as CSV after approval' do
    annotation.annotation_points.create!(x: 10, y: 20)
    login_as(reviewer)
    save_points([{ x: 55, y: 65, source_id: nil }])
    post approve_tile_path(tile), params: { correction_version: annotation.reload.review_correction.lock_version },
         headers: { 'ACCEPT' => 'application/json' }
    expect(response).to have_http_status(:ok)
    login_as(admin)
    get export_points_csv_tile_path(tile)
    expect(response).to have_http_status(:ok)
    expect(CSV.parse(response.body)).to eq([%w[x y], %w[55.0 65.0]])

    get export_bundle_tiles_path
    expect(response).to have_http_status(:ok)
    Zip::File.open_buffer(response.body) do |zip|
      final_csv = zip.read("tile_#{tile.id}/pontos_finais.csv")
      expect(CSV.parse(final_csv)).to eq([%w[x y], %w[55.0 65.0]])
    end
  end

  it 'rejects forged source identities and editing after approval' do
    login_as(reviewer)
    save_points([{ x: 11, y: 20, source_id: 1 }])
    expect(response).to have_http_status(:unprocessable_entity)
    expect(annotation.reload.review_correction).to be_nil
    post approve_tile_path(tile), headers: { 'ACCEPT' => 'application/json' }
    expect(response).to have_http_status(:ok)
    save_points([])
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'uses the submitted annotation for tiles without a point set' do
    point_set.destroy!
    annotation.annotation_points.create!(x: 12, y: 34)
    login_as(reviewer)
    get zen_plot_points_tile_path(tile, format: :json)
    expect(JSON.parse(response.body)['points']).to eq([{ 'id' => 1, 'x' => 12, 'y' => 34 }])
    save_points([{ x: 12, y: 34, source_id: 1 }])
    expect(response).to have_http_status(:ok)
    expect(annotation.reload.review_correction.added_count).to eq(0)
  end
end
