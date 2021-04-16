require "sidekiq/web"

Rails.application.routes.draw do
  namespace :admin do
    authenticate :user, lambda { |u| u.has_role?(:volunteer) } do
      get "/" => "home#index"

      authenticate :user, lambda { |u| u.has_role?(:supply_member) } do
        # Supply
        resources :vaccination_centers do
          authenticate :user, lambda { |u| u.has_role?(:supply_admin) } do
            # Supply Admin
            patch :validate, on: :member
            patch :disable, on: :member
            patch :enable, on: :member
            post :add_partner, on: :member
          end
        end
      end

      authenticate :user, lambda { |u| u.has_role?(:supply_admin) } do
        # Supply admin
        get "/stats" => "stats#stats"
        post "/stats" => "stats#stats"
      end

      authenticate :user, lambda { |u| u.has_role?(:support_member) } do
        # Support
        resources :users, only: [:index, :destroy] do
          post :resend_confirmation, on: :member
        end
      end

      authenticate :user, lambda { |u| u.has_role?(:ds_admin) } do
        # DataScience admin
        mount Blazer::Engine, at: "/blazer"
      end

      authenticate :user, lambda { |u| u.has_role?(:dev_admin) } do
        # Dev admin
        mount Flipper::UI.app(Flipper), at: "/flipper", as: :flipper_ui
      end

      authenticate :user, lambda { |u| u.has_role?(:admin) } do
        # Core Team
        resources :power_users, only: [:index]
      end

      authenticate :user, lambda { |u| u.has_role?(:super_admin) } do
        # Super Admin
        mount PgHero::Engine, at: "/pghero"
        mount Sidekiq::Web => "/sidekiq"
      end
    end
  end

  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?

  ## devise users
  devise_for :users,
    path_names: {sign_in: "login", sign_out: "logout"},
    skip: %i[sessions registrations],
    controllers: {
      confirmations: "confirmations"
    }

  # TODO FIXME Legacy hardcoced login/logout routes, we should use the routes from devise instead
  devise_scope :user do
    get "login", to: "devise/sessions#new", as: :new_user_session
    post "login", to: "devise/sessions#create", as: :user_session
    delete "logout", to: "devise/sessions#destroy", as: :destroy_user_session
  end

  ## devise partners
  devise_for :partners,
    path_names: {sign_in: "login", sign_out: "logout"},
    skip: %i[registrations],
    controllers: {
      confirmations: "confirmations"
    }

  ####################

  ## users
  resources :users, only: [:create, :new]
  get "/profile" => "users#show", :as => :profile
  put "/profile" => "users#update", :as => :user
  delete "/profile" => "users#delete", :as => :delete_user
  get "/users" => "users#new"

  ## Partners
  resources :partners, only: [:new, :create]
  resource :partners, only: [:show, :update, :destroy]
  get "/partenaires", to: redirect("/partenaires/inscription", status: 302)
  get "/partenaires/inscription" => "partners#new", :as => :partenaires_inscription

  namespace :partners do
    resources :vaccination_centers, only: [:index, :show, :new, :create] do
      resources :campaigns, only: [:new, :create] do
        post :simulate_reach, on: :collection
      end
    end
    resources :campaigns, only: [:show, :update]
  end

  ## matches
  resources :matches, only: [:show, :update, :destroy], param: :match_confirmation_token

  ## Pages
  get "/carte" => "pages#carte", :as => :carte
  get "/benevoles" => "pages#benevoles", :as => :benevoles
  get "/contact" => "pages#contact", :as => :contact
  get "/algorithme" => "pages#algorithme", :as => :algorithme
  get "/presse" => "pages#presse", :as => :presse
  get "/faq" => "pages#faq", :as => :faq

  ## Pages from frozen_records/static_pages.yml
  get "/mentions_legales" => "pages#mentions_legales", :as => :mentions_legales
  get "/cgu_volontaires" => "pages#cgu_volontaires", :as => :cgu_volontaires
  get "/cgu_pro" => "pages#cgu_pro", :as => :cgu_pro
  get "/privacy_volontaires" => "pages#privacy_volontaires", :as => :privacy_volontaires
  get "/privacy_pro" => "pages#privacy_pro", :as => :privacy_pro
  get "/cookies" => "pages#cookies", :as => :cookies

  ## Redirections
  get "/privacy" => redirect("/privacy_volontaires") # 301

  ## robots.txt
  get "/robots.txt", to: "pages#robots"

  root to: "users#new"
end
