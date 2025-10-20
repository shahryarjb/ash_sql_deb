defmodule AshSqlDeb.MishkaBlog do
  use Ash.Domain,
    otp_app: :ash_sql_deb,
    extensions: [
      AshPaperTrail.Domain,
      AshJsonApi.Domain
    ]

  paper_trail do
    include_versions?(true)
  end

  json_api do
    open_api do
      tag "MishkaBlog"
      group_by :domain
    end

    routes do
      base_route "/v1/tenant/admin/mishka-blog/auto-posting", AshSqlDeb.MishkaBlog.AutoPosting do
        index :read
        get :read
        get :by_plugin, route: "/by-plugin/:plugin"
        index :active, route: "/active"
        index :archived, route: "/archived"
        get :archived, route: "/archived/:id"
        post :create
        patch :update
        patch :activate, route: "/:id/activate"
        patch :deactivate, route: "/:id/deactivate"
        patch :unarchive, route: "/:id/unarchive", read_action: :get_archived
        delete :destroy, route: "/:id/archive"
        delete :permanent_destroy, route: "/:id/permanent"
      end
    end
  end

  resources do
    resource AshSqlDeb.MishkaBlog.AutoPosting
  end
end
