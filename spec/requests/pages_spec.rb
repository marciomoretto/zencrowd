require 'rails_helper'

RSpec.describe "Pages", type: :request do
  describe "GET /sobre" do
    it "returns http success" do
      get "/sobre"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /contato" do
    it "returns http success" do
      get "/contato"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /ajuda" do
    it "returns http success" do
      get "/ajuda"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /faq" do
    it "returns http success" do
      get "/faq"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /documentacao" do
    it "returns http success" do
      get "/documentacao"
      expect(response).to have_http_status(:success)
    end
  end

end
