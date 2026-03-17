	def human_image_status(status)
		I18n.t("activerecord.attributes.image.statuses.#{status}", default: status.to_s.humanize)
	end
module ApplicationHelper
	# Retorna um array de hashes com os links de navegação para o usuário autenticado
	def navigation_links_for(user)
		return [] unless user

		case
		when user.admin?
			[
				{ path: images_path, icon: 'bi-images', label: 'Imagens' },
				{ path: new_image_path, icon: 'bi-upload', label: 'Upload de Imagem' },
				{ path: export_dataset_path, icon: 'bi-download', label: 'Exportar Dataset' }
			]
		when user.annotator?
			[
				{ path: available_images_path, icon: 'bi-images', label: 'Imagens Disponíveis' },
				{ path: my_task_path, icon: 'bi-pencil-square', label: 'Minha Tarefa' }
			]
		when user.reviewer?
			[
				{ path: review_tasks_path, icon: 'bi-check-circle', label: 'Tarefas em Revisão' }
			]
		else
			[]
		end
	end
end
