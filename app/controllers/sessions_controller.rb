  # GET /login
  def new
    respond_to do |format|
      format.html # renderiza new.html.erb
      format.json { head :not_acceptable }
    end
  end
class SessionsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:create, :destroy]

  # POST /login
  def create
    user = User.find_by(email: params[:email])

    respond_to do |format|
      if user&.authenticate(params[:password])
        session[:user_id] = user.id
        format.html do
          flash[:notice] = "Login realizado com sucesso!"
          redirect_to root_path
        end
        format.json do
          render json: {
            user: {
              id: user.id,
              email: user.email,
              name: user.name,
              role: user.role
            }
          }, status: :ok
        end
      else
        format.html do
          flash.now[:error] = "Email ou senha inválidos"
          render :new, status: :unprocessable_entity
        end
        format.json do
          render json: { error: 'Email ou senha inválidos' }, status: :unauthorized
        end
      end
    end
  end

  # DELETE /logout
  def destroy
    session[:user_id] = nil
    respond_to do |format|
      format.html do
        flash[:notice] = "Logout realizado com sucesso."
        redirect_to root_path
      end
      format.json { head :no_content }
    end
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
