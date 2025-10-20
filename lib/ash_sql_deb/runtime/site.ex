defmodule AshSqlDeb.Runtime.Site do
  use Ash.Resource,
    otp_app: :ash_sql_deb,
    domain: AshSqlDeb.Runtime,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshArchival.Resource, AshSlug, AshJsonApi.Resource],
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query

  postgres do
    table "sites"
    repo AshSqlDeb.Repo
    # Database-level optimization for archived records
    base_filter_sql "(archived_at IS NULL)"

    check_constraints do
      check_constraint :name, "name_length_check",
        check: "length(name) >= 3 AND length(name) <= 70",
        message: "Name must be between 3 and 70 characters"

      check_constraint :host, "host_length_check",
        check: "length(host) >= 3 AND length(host) <= 200",
        message: "Host must be between 3 and 200 characters"

      check_constraint :priority, "priority_range_check",
        check: "priority >= 0 AND priority <= 100",
        message: "Priority must be between 0 and 100"

      check_constraint :mode, "mode_values_check",
        check: "mode IN ('api_only', 'phoenix_only', 'hybrid')",
        message: "Mode must be one of: api_only, phoenix_only, hybrid"

      # Multiple attributes can share the same constraint
      check_constraint [:name, :host], "no_empty_strings",
        check: "name != '' AND host != ''",
        message: "Name and host cannot be empty"
    end
  end

  # Soft deletion configuration using archived_at timestamp
  archive do
    # base_filter? false
    exclude_read_actions([:archived, :get_archived, :get_any])
    exclude_destroy_actions([:permanent_destroy])
  end

  # JSON API configuration for REST endpoints
  json_api do
    type "site"
    default_fields [:id, :name, :host, :priority, :active]
  end

  actions do
    defaults [:read, :destroy]

    default_accept [
      :name,
      :host,
      :priority,
      :active,
      :master,
      :mode,
      :frontend_domain,
      :allowed_origins
    ]

    create :create do
      primary? true

      validate present([:name, :host])
      validate one_of(:mode, ["api_only", "phoenix_only", "hybrid"])

      change slugify(:name, into: :name)

      description "Creates site with validated name and host domain, ensuring unique identification"
    end

    update :update do
      primary? true
      require_atomic? false

      validate absent(:archived_at) do
        message "Cannot edit archived site. Please unarchive it first."
      end

      validate one_of(:mode, ["api_only", "phoenix_only", "hybrid"])

      change slugify(:name, into: :name)

      description "Updates active site configuration, preventing changes to archived sites"
    end

    read :by_priority do
      description "Lists sites ordered by priority for host matching precedence"
      pagination offset?: true, default_limit: 100
      prepare build(sort: [priority: :desc, name: :asc])
    end

    read :get_any do
      description "Retrieves single site by ID including archived sites"
      get? true
    end

    read :get_archived do
      description "Retrieves single archived site for recovery or inspection"
      get? true
      filter expr(not is_nil(archived_at))
    end

    read :archived do
      description "Lists all archived sites for bulk recovery management"
      pagination offset?: true, default_limit: 100
      filter expr(not is_nil(archived_at))
    end

    update :activate do
      accept []
      change set_attribute(:active, true)
      description "Enables a site to handle incoming requests and serve content"
    end

    update :deactivate do
      accept []
      change set_attribute(:active, false)
      description "Disables a site without archiving, temporarily preventing access"
    end

    update :unarchive do
      accept []
      change set_attribute(:archived_at, nil)
      atomic_upgrade_with :archived
      description "Restores archived site to active status, enabling modifications"
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints min_length: 3, max_length: 70, trim?: true

      description "Human-readable site name"
    end

    attribute :host, :string do
      allow_nil? false
      public? true
      constraints min_length: 3, max_length: 200, trim?: true
      description "Domain name for the site (e.g., example.com)"
    end

    attribute :priority, :integer do
      default 0
      public? true
      constraints min: 0, max: 100
      description "Priority for site routing (higher = more priority)"
    end

    attribute :active, :boolean do
      default true
      public? true
      description "Whether the site is currently active"
    end

    attribute :mode, :string do
      default "hybrid"
      public? true

      description "Site operation mode: 'api_only' (headless), 'phoenix_only' (LiveView only), 'hybrid' (both API and LiveView)"
    end

    attribute :frontend_domain, :string do
      allow_nil? true
      public? true
      constraints min_length: 3, max_length: 200, trim?: true
      description "Frontend application domain for API-only sites (e.g., app.example.com)"
    end

    attribute :allowed_origins, {:array, :string} do
      default []
      public? true
      description "Additional allowed CORS origins for API access"
    end

    attribute :master, :boolean do
      default false
      public? true
      description "Whether this site is the master site (only one allowed)"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_name, [:name] do
      description "Ensures site names are globally unique for clear identification"
      message "Site name must be unique"
    end

    identity :unique_host, [:host] do
      description "Prevents host conflicts ensuring proper domain-based routing"
      message "Host must be unique"
    end
  end
end
