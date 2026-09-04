require "sidekiq/web"

Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  mount ActionCable.server => "/cable"
  mount Sidekiq::Web => "/sidekiq" if Rails.env.development?

  get "metrics", to: "metrics#show"
  get "metrics/prometheus", to: "metrics#prometheus"

  resources :flash_sales, only: %i[show create] do
    resource :queue, only: [:create], controller: "queue"
    get "queue/:user_token", to: "queue#show", as: :queue_status
    resource :checkout, only: [:create], controller: "checkout"
  end
end
