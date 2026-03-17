class SessionsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:create, :destroy]

  # POST /login
  def create
    user = User.find_by(email: params[:email])

    if user&.authenticate(params[:password])
      session[:user_id] = user.id
      render json: { 
        user: {
          id: user.id,
          email: user.email,
          name: user.name,
          role: user.role
        }
      }, status: :ok
    else
      render json: { error: 'Email ou senha inválidos' }, status: :unauthorized
    end
  end

  # DELETE /logout
  def destroy
    session[:user_id] = nil
    head :no_content
  end

  # GET /me
  def show
    if current_user
      render json: { 
        user: {
          id: current_user.id,
          email: current_user.email,
          name: current_user.name,
          role: current_user.role
        }
      }, status: :ok
    else
      render json: { error: 'Não autenticado' }, status: :unauthorized
    end
  end
end
