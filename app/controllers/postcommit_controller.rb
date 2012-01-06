class PostcommitController < ApplicationController

  def create
    @payload = ActiveSupport::JSON.decode params[:payload]

    redirect_to :action => 'show'
  end

end
