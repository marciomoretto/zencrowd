class Admin::ImagesController < ApplicationController
  before_action :require_admin!

  def index
    @images = Image.order(id: :desc)
  end

  private

  def require_admin!
    unless current_user&.admin?
      redirect_to root_path, alert: 'Acesso restrito ao administrador.'
    end
  end
end
