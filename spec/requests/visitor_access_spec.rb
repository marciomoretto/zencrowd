require 'rails_helper'

RSpec.describe 'Visitor access', type: :request do
  let(:visitor) do
    create(
      :user,
      :visitor,
      email: 'visitor@example.com',
      password: 'password123',
      password_confirmation: 'password123',
      onboarding_completed: true
    )
  end

  before do
    post '/login', params: { email: visitor.email, password: 'password123' }
  end

  it 'allows visitor to access own profile page' do
    get '/meus-dados'

    expect(response).to have_http_status(:ok)
  end

  it 'blocks visitor from dashboard and redirects to meus dados' do
    get '/dashboard'

    expect(response).to redirect_to(meus_dados_path)
    expect(flash[:alert]).to eq('Permissão negada')
  end

  it 'redirects authenticated visitor from root to meus dados' do
    get '/'

    expect(response).to redirect_to(meus_dados_path)
  end
end
