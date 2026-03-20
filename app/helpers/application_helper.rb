module ApplicationHelper
	def human_tile_status(status)
		status_key = status.to_s
		fallback_labels = {
			'available' => 'Disponível',
			'reserved' => 'Reservada',
			'submitted' => 'Submetida',
			'in_review' => 'Em revisão',
			'approved' => 'Aprovada',
			'rejected' => 'Rejeitada',
			'paid' => 'Paga'
		}

		I18n.t("activerecord.attributes.image.statuses.#{status_key}", default: fallback_labels[status_key] || status_key.humanize)
	end

	def human_image_status(status)
		human_tile_status(status)
	end

	def tile_status_button_class(status)
		case status.to_s
		when 'available'
			'btn btn-sm btn-outline-success disabled'
		when 'reserved'
			'btn btn-sm btn-outline-warning disabled'
		when 'submitted'
			'btn btn-sm btn-info disabled text-dark'
		when 'in_review'
			'btn btn-sm btn-outline-primary disabled'
		when 'approved'
			'btn btn-sm btn-success disabled'
		when 'rejected'
			'btn btn-sm btn-danger disabled'
		when 'paid'
			'btn btn-sm btn-dark disabled'
		else
			'btn btn-sm btn-secondary disabled'
		end
	end

	def human_review_status(status)
		status_key = status.to_s
		fallback_labels = {
			'approved' => 'Aprovada',
			'rejected' => 'Rejeitada'
		}

		I18n.t("activerecord.attributes.review.statuses.#{status_key}", default: fallback_labels[status_key] || status_key.humanize)
	end

	# Retorna os links de navegação por papel do usuário autenticado.
	def navigation_links_for(user)
		return [] unless user

		case
		when user.admin?
			[
				{ path: dashboard_path, icon: 'bi-speedometer2', label: 'Dashboard' },
				{ path: admin_eventos_path, icon: 'bi-calendar-event', label: 'Eventos' },
				{ path: imagens_path, icon: 'bi-image', label: 'Imagens' },
				{ path: tiles_path, icon: 'bi-grid-3x3-gap', label: 'Tiles' },
				{ path: admin_users_path, icon: 'bi-people', label: 'Usuários' }
			]
		when user.annotator?
			[
				{ path: dashboard_path, icon: 'bi-speedometer2', label: 'Dashboard' },
				{ path: available_tiles_path, icon: 'bi-grid-3x3-gap', label: 'Tiles Disponíveis' },
				{ path: my_task_path, icon: 'bi-pencil-square', label: 'Minha Tarefa' }
			]
		when user.reviewer?
			[
				{ path: dashboard_path, icon: 'bi-speedometer2', label: 'Dashboard' },
				{ path: reviewer_reviews_path, icon: 'bi-check-circle', label: 'Tarefas em Revisão' }
			]
		else
			[]
		end
	end
end
