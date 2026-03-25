class ContatoMailer < ApplicationMailer
  # O e-mail da sua equipe que vai receber as mensagens
  default to: 'monitordodebatepolitico@gmail.com' 

  def nova_mensagem(nome, email, mensagem)
    @nome = nome
    @email = email
    @mensagem = mensagem
    
    # Monta o e-mail. O "from" é quem preencheu o formulário.
    mail(from: @email, subject: "Novo contato via site ZenCrowd - de #{@nome}")
  end
end