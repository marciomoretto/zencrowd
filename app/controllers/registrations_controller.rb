class RegistrationsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:create]
  before_action :redirect_authenticated_user_to_dashboard!, only: [:new, :create]
  layout 'public'

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
          redirect_to dashboard_path
        end
        format.json { render json: { user: @user }, status: :created }
      end
    else
      respond_to do |format|
        format.html do
          render :new, status: :unprocessable_entity
        end
        format.json { render json: { errors: @user.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  private

  def user_params
    up = params.require(:user).permit(:name, :email, :password, :password_confirmation, :role)
    up[:role] = nil if up[:role].blank?
    up
  end
end
