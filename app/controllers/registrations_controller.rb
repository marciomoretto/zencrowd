class RegistrationsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:create]

  # GET /signup
  def new
    @user = User.new
    respond_to do |format|
      format.html # new.html.erb
      format.json { head :not_acceptable }
    end
  end

  # POST /signup
  def create
    @user = User.new(user_params)
    if @user.save
      session[:user_id] = @user.id
      respond_to do |format|
        format.html do
          flash[:notice] = "Cadastro realizado com sucesso!"
          redirect_to root_path
        end
        format.json { render json: { user: @user }, status: :created }
      end
    else
      respond_to do |format|
        format.html do
          flash.now[:error] = @user.errors.full_messages.to_sentence
          render :new, status: :unprocessable_entity
        end
        format.json { render json: { errors: @user.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  private

  def user_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation, :role)
  end
end
