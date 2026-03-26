class Uploader::DroneSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_uploader!

  def show
    @drones = Drone.order(:modelo, :lente)
    @drone = Drone.new(aspect_ratio: '4:3')
  end

  def create
    @drone = Drone.new(drone_params)

    if @drone.save
      redirect_to uploader_drone_settings_path, notice: 'Drone cadastrado com sucesso.'
    else
      @drones = Drone.order(:modelo, :lente)
      render :show, status: :unprocessable_entity
    end
  end

  private

  def drone_params
    params.require(:drone).permit(:modelo, :lente, :fov_diag_deg, :aspect_ratio)
  end
end
