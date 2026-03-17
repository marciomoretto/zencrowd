	def human_image_status(status)
		I18n.t("activerecord.attributes.image.statuses.#{status}", default: status.to_s.humanize)
	end
module ApplicationHelper
end
