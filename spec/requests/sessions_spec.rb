require 'rails_helper'

RSpec.describe 'Sessions', type: :request do
  describe 'POST /login' do
    let!(:user) { User.create!(email: 'test@example.com', name: 'Test User', role: :annotator, password: 'password123') }

    context 'with valid credentials' do
      it 'returns user data and sets session' do
        post '/login', params: { email: 'test@example.com', password: 'password123' }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['user']['email']).to eq('test@example.com')
        expect(json['user']['name']).to eq('Test User')
        expect(json['user']['role']).to eq('annotator')
        expect(session[:user_id]).to eq(user.id)
      end
    end

    context 'with invalid email' do
      it 'returns unauthorized error' do
        post '/login', params: { email: 'wrong@example.com', password: 'password123' }

        expect(response).to have_http_status(:unauthorized)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Email ou senha inválidos')
        expect(session[:user_id]).to be_nil
      end
    end

    context 'with invalid password' do
      it 'returns unauthorized error' do
        post '/login', params: { email: 'test@example.com', password: 'wrongpassword' }

        expect(response).to have_http_status(:unauthorized)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Email ou senha inválidos')
        expect(session[:user_id]).to be_nil
      end
    end
  end

  describe 'DELETE /logout' do
    let!(:user) { User.create!(email: 'test@example.com', name: 'Test User', role: :annotator, password: 'password123') }

    context 'when logged in' do
      before do
        post '/login', params: { email: 'test@example.com', password: 'password123' }
      end

      it 'clears the session' do
        expect(session[:user_id]).to eq(user.id)

        delete '/logout'

        expect(response).to have_http_status(:no_content)
        expect(session[:user_id]).to be_nil
      end
    end
  end

  describe 'GET /me' do
    let!(:user) { User.create!(email: 'test@example.com', name: 'Test User', role: :annotator, password: 'password123') }

    context 'when logged in' do
      before do
        post '/login', params: { email: 'test@example.com', password: 'password123' }
      end

      it 'returns current user data' do
        get '/me'

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['user']['email']).to eq('test@example.com')
        expect(json['user']['name']).to eq('Test User')
        expect(json['user']['role']).to eq('annotator')
      end
    end

    context 'when not logged in' do
      it 'returns unauthorized error' do
        get '/me'

        expect(response).to have_http_status(:unauthorized)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Não autenticado')
      end
    end
  end
end
