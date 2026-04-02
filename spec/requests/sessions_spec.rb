require 'rails_helper'

RSpec.describe 'Sessions', type: :request do
  describe 'GET /login' do
    it 'renderiza formulário de login local no ambiente de teste' do
      get '/login'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Entrar')
    end
  end

  describe 'GET /auth/usp/callback' do
    let(:client) { instance_double(SenhaUnicaUSP::Client) }

    before do
      allow(SenhaUnicaUSP::Client).to receive(:new).and_return(client)
    end

    it 'creates first-login user and redirects to onboarding' do
      allow(client).to receive(:fetch_payload!).and_return(
        'loginUsuario' => '1234567',
        'nomeUsuario' => 'Joao USP',
        'emailPrincipalUsuario' => 'joao@usp.br'
      )

      expect do
        get '/auth/usp/callback', params: { oauth_verifier: 'verifier-token' }
      end.to change(User, :count).by(1)

      user = User.order(:id).last
      expect(user.usp_login).to eq('1234567')
      expect(user.email).to eq('joao@usp.br')
      expect(user.name).to eq('Joao USP')
      expect(user.role).to eq('annotator')
      expect(user.onboarding_completed).to be(false)
      expect(session[:user_id]).to eq(user.id)
      expect(response).to redirect_to(onboarding_path)
    end

    it 'promotes user to admin when usp login is configured as admin' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('USP_ADMIN_LOGINS', '').and_return('1234567')

      allow(client).to receive(:fetch_payload!).and_return(
        'loginUsuario' => '1234567',
        'nomeUsuario' => 'Joao USP',
        'emailPrincipalUsuario' => 'joao@usp.br'
      )

      get '/auth/usp/callback', params: { oauth_verifier: 'verifier-token' }

      user = User.find(session[:user_id])
      expect(user.usp_login).to eq('1234567')
      expect(user.role).to eq('admin')
    end

    it 'does not overwrite local name/email for existing USP user and redirects to dashboard' do
      user = User.create!(
        usp_login: '1234567',
        email: 'local@zencrowd.org',
        name: 'Nome Local',
        role: :reviewer,
        onboarding_completed: true,
        cpf: '12345678901',
        pix_key_type: 'random',
        pix_key: 'local@pix.com',
        password: 'password123'
      )

      allow(client).to receive(:fetch_payload!).and_return(
        'loginUsuario' => '1234567',
        'nomeUsuario' => 'Nome vindo da USP',
        'emailPrincipalUsuario' => 'usp@usp.br'
      )

      get '/auth/usp/callback', params: { oauth_verifier: 'verifier-token' }

      expect(response).to redirect_to(dashboard_path)
      expect(session[:user_id]).to eq(user.id)

      user.reload
      expect(user.name).to eq('Nome Local')
      expect(user.email).to eq('local@zencrowd.org')
    end

    it 'rejects blocked user and clears session' do
      User.create!(
        usp_login: '9999999',
        email: 'blocked@usp.br',
        name: 'Blocked',
        role: :annotator,
        onboarding_completed: true,
        cpf: '99999999999',
        pix_key_type: 'random',
        pix_key: 'blocked@pix.com',
        blocked: true,
        password: 'password123'
      )

      allow(client).to receive(:fetch_payload!).and_return(
        'loginUsuario' => '9999999',
        'nomeUsuario' => 'Blocked',
        'emailPrincipalUsuario' => 'blocked@usp.br'
      )

      get '/auth/usp/callback', params: { oauth_verifier: 'verifier-token' }

      expect(response).to redirect_to(root_path)
      expect(session[:user_id]).to be_nil
    end
  end

  describe 'Onboarding' do
    let(:client) { instance_double(SenhaUnicaUSP::Client) }

    before do
      allow(SenhaUnicaUSP::Client).to receive(:new).and_return(client)
      allow(client).to receive(:fetch_payload!).and_return(
        'loginUsuario' => '7654321',
        'nomeUsuario' => 'Maria USP',
        'emailPrincipalUsuario' => 'maria@usp.br'
      )
      get '/auth/usp/callback', params: { oauth_verifier: 'verifier-token' }
    end

    it 'requires pix key to complete onboarding' do
      patch '/onboarding', params: { user: { cpf: '12345678901', phone: '11999998888', pix_key_type: 'phone', pix_key: '' } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(User.find(session[:user_id]).onboarding_completed).to be(false)
    end

    it 'requires cpf to complete onboarding' do
      patch '/onboarding', params: { user: { cpf: '', phone: '11999998888', pix_key_type: 'random', pix_key: 'ABCD1234EFGH5678' } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(User.find(session[:user_id]).onboarding_completed).to be(false)
    end

    it 'requires pix key type to complete onboarding' do
      patch '/onboarding', params: { user: { cpf: '12345678901', phone: '11999998888', pix_key_type: '', pix_key: '12345678901' } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(User.find(session[:user_id]).onboarding_completed).to be(false)
    end

    it 'completes onboarding with pix key and redirects to dashboard' do
      patch '/onboarding', params: { user: { cpf: '12345678901', phone: '11999998888', pix_key_type: 'phone', pix_key: '11999998888' } }

      expect(response).to redirect_to(dashboard_path)
      user = User.find(session[:user_id])
      expect(user.cpf).to eq('12345678901')
      expect(user.phone).to eq('11999998888')
      expect(user.pix_key_type).to eq('phone')
      expect(user.pix_key).to eq('11999998888')
      expect(user.onboarding_completed).to be(true)
    end
  end

  describe 'DELETE /logout' do
    it 'clears the session and redirects to root' do
      client = instance_double(SenhaUnicaUSP::Client)
      allow(SenhaUnicaUSP::Client).to receive(:new).and_return(client)
      allow(client).to receive(:fetch_payload!).and_return(
        'loginUsuario' => '1111111',
        'nomeUsuario' => 'Logout User',
        'emailPrincipalUsuario' => 'logout@usp.br'
      )

      get '/auth/usp/callback', params: { oauth_verifier: 'verifier-token' }
      delete '/logout'

      expect(response).to redirect_to(root_path)
      expect(session[:user_id]).to be_nil
    end
  end
end
