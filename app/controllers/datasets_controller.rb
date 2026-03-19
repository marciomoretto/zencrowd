class DatasetsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!

  def export
    # Stub: lógica de exportação de dataset
    flash[:notice] = 'Exportação de dataset não implementada.'
    redirect_to tiles_path
  end
end
