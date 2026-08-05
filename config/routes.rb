Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  require "sidekiq/web"
  mount Sidekiq::Web => "/sidekiq"

  resources :flash_sales, only: [:show] do
    resource :queue, only: [:create], controller: "queue"
    get "queue/:user_token", to: "queue#show", as: :queue_status
    resource :checkout, only: [:create], controller: "checkout"
  end
end
