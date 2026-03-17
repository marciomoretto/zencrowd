require 'rails_helper'

RSpec.describe 'Image Transitions API', type: :request do
  let!(:admin) { create(:user, :admin) }
  let!(:annotator) { create(:user, :annotator) }
  let!(:reviewer) { create(:user, :reviewer) }
  let!(:image) { create(:image, uploader: admin, status: :available) }

  def login_as(user)
    post '/login', params: { email: user.email, password: 'password123' }
  end

  describe 'POST /images/:id/reserve' do
    context 'when logged in as annotator' do
      before { login_as(annotator) }

      it 'reserves an available image' do
        post "/images/#{image.id}/reserve"

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['status']).to eq('reserved')
        expect(json['reserver']['id']).to eq(annotator.id)
        expect(json['reserved_at']).to be_present
      end

      it 'returns error when image is not available' do
        image.update!(status: :reserved)
        post "/images/#{image.id}/reserve"

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Image is not available')
      end

      it 'returns error when user already has a reserved image' do
        other_image = create(:image, uploader: admin, status: :available)
        image.reserve!(annotator)

        post "/images/#{other_image.id}/reserve"

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('User already has a reserved image')
      end
    end

    context 'when logged in as reviewer' do
      before { login_as(reviewer) }

      it 'returns forbidden' do
        post "/images/#{image.id}/reserve"

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when not logged in' do
      it 'returns unauthorized' do
        post "/images/#{image.id}/reserve"

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /images/:id/submit' do
    before do
      image.update!(status: :reserved, reserver: annotator, reserved_at: Time.current)
    end

    context 'when logged in as the reserver' do
      before { login_as(annotator) }

      it 'submits the annotation' do
        post "/images/#{image.id}/submit"

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['status']).to eq('submitted')
      end

      it 'returns error when image is not reserved' do
        image.update!(status: :available)
        post "/images/#{image.id}/submit"

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Image is not reserved')
      end
    end

    context 'when logged in as different annotator' do
      let(:other_annotator) { create(:user, :annotator) }
      before { login_as(other_annotator) }

      it 'returns error' do
        post "/images/#{image.id}/submit"

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Only the reserver can submit')
      end
    end

    context 'when not logged in' do
      it 'returns unauthorized' do
        post "/images/#{image.id}/submit"

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /images/:id/start_review' do
    before do
      image.update!(status: :submitted)
    end

    context 'when logged in as reviewer' do
      before { login_as(reviewer) }

      it 'starts review' do
        post "/images/#{image.id}/start_review"

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['status']).to eq('in_review')
      end

      it 'returns error when image is not submitted' do
        image.update!(status: :available)
        post "/images/#{image.id}/start_review"

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Image is not submitted')
      end
    end

    context 'when logged in as annotator' do
      before { login_as(annotator) }

      it 'returns forbidden' do
        post "/images/#{image.id}/start_review"

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when not logged in' do
      it 'returns unauthorized' do
        post "/images/#{image.id}/start_review"

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /images/:id/approve' do
    before do
      image.update!(status: :in_review)
    end

    context 'when logged in as reviewer' do
      before { login_as(reviewer) }

      it 'approves the annotation' do
        post "/images/#{image.id}/approve"

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['status']).to eq('approved')
      end

      it 'returns error when image is not in review' do
        image.update!(status: :submitted)
        post "/images/#{image.id}/approve"

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Image is not in review')
      end
    end

    context 'when logged in as annotator' do
      before { login_as(annotator) }

      it 'returns forbidden' do
        post "/images/#{image.id}/approve"

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when not logged in' do
      it 'returns unauthorized' do
        post "/images/#{image.id}/approve"

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /images/:id/reject' do
    before do
      image.update!(status: :in_review, reserver: annotator, reserved_at: 1.hour.ago)
    end

    context 'when logged in as reviewer' do
      before { login_as(reviewer) }

      it 'rejects the annotation' do
        post "/images/#{image.id}/reject"

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['status']).to eq('reserved')
        expect(json['reserver']['id']).to eq(annotator.id)
      end

      it 'returns error when image is not in review' do
        image.update!(status: :submitted)
        post "/images/#{image.id}/reject"

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Image is not in review')
      end
    end

    context 'when logged in as annotator' do
      before { login_as(annotator) }

      it 'returns forbidden' do
        post "/images/#{image.id}/reject"

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when not logged in' do
      it 'returns unauthorized' do
        post "/images/#{image.id}/reject"

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /images/:id/mark_paid' do
    before do
      image.update!(status: :approved)
    end

    context 'when logged in as admin' do
      before { login_as(admin) }

      it 'marks image as paid' do
        post "/images/#{image.id}/mark_paid"

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['status']).to eq('paid')
      end

      it 'returns error when image is not approved' do
        image.update!(status: :in_review)
        post "/images/#{image.id}/mark_paid"

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Image is not approved')
      end
    end

    context 'when logged in as annotator' do
      before { login_as(annotator) }

      it 'returns forbidden' do
        post "/images/#{image.id}/mark_paid"

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when not logged in' do
      it 'returns unauthorized' do
        post "/images/#{image.id}/mark_paid"

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /images/:id/expire_reservation' do
    before do
      image.update!(status: :reserved, reserver: annotator, reserved_at: Time.current)
    end

    context 'when logged in as admin' do
      before { login_as(admin) }

      it 'expires the reservation' do
        post "/images/#{image.id}/expire_reservation"

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['status']).to eq('available')
        expect(json['reserver']).to be_nil
        expect(json['reserved_at']).to be_nil
      end

      it 'returns error when image is not reserved' do
        image.update!(status: :available)
        post "/images/#{image.id}/expire_reservation"

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Image is not reserved')
      end
    end

    context 'when logged in as annotator' do
      before { login_as(annotator) }

      it 'returns forbidden' do
        post "/images/#{image.id}/expire_reservation"

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when not logged in' do
      it 'returns unauthorized' do
        post "/images/#{image.id}/expire_reservation"

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'complete workflow' do
    it 'follows the happy path from available to paid' do
      # Reserve
      login_as(annotator)
      post "/images/#{image.id}/reserve"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['status']).to eq('reserved')

      # Submit
      post "/images/#{image.id}/submit"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['status']).to eq('submitted')

      # Start review
      login_as(reviewer)
      post "/images/#{image.id}/start_review"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['status']).to eq('in_review')

      # Approve
      post "/images/#{image.id}/approve"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['status']).to eq('approved')

      # Mark paid
      login_as(admin)
      post "/images/#{image.id}/mark_paid"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['status']).to eq('paid')
    end
  end
end
