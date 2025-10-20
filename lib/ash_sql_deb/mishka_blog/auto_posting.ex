defmodule AshSqlDeb.MishkaBlog.AutoPosting do
  use Ash.Resource,
    otp_app: :ash_sql_deb,
    domain: AshSqlDeb.MishkaBlog,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshArchival.Resource, AshPaperTrail.Resource, AshJsonApi.Resource],
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query
  alias AshSqlDeb.MishkaBlog.Resources.Validations

  @admin_fields [
    :name,
    :plugin,
    :description,
    :is_active,
    :config,
    :site_id
  ]
  postgres do
    table "auto_postings"
    repo AshSqlDeb.Repo

    # Database-level optimization for archived records
    base_filter_sql "(archived_at IS NULL)"

    custom_indexes do
      index [:plugin, :site_id], unique: true
      index [:is_active]
    end

    check_constraints do
      check_constraint :name, "name_length",
        check: "length(name) >= 1 AND length(name) <= 255",
        message: "Name must be between 1 and 255 characters"

      check_constraint :plugin, "plugin_length",
        check: "length(plugin) >= 1 AND length(plugin) <= 255",
        message: "Plugin must be between 1 and 255 characters"
    end

    # Database-level trigger to prevent updates on archived records
    custom_statements do
      statement :prevent_archived_auto_posting_updates_function do
        up """
        CREATE OR REPLACE FUNCTION prevent_archived_auto_posting_updates()
        RETURNS TRIGGER AS $$
        BEGIN
          -- Allow unarchiving (archived_at: NOT NULL -> NULL)
          IF OLD.archived_at IS NOT NULL AND NEW.archived_at IS NULL THEN
            RETURN NEW;
          END IF;

          -- Prevent other updates on archived records
          IF OLD.archived_at IS NOT NULL THEN
            RAISE EXCEPTION 'Cannot update archived auto-posting configuration'
              USING ERRCODE = 'check_violation';
          END IF;

          RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
        """

        down "DROP FUNCTION IF EXISTS prevent_archived_auto_posting_updates();"
      end

      statement :prevent_archived_auto_posting_updates_trigger do
        up """
        CREATE TRIGGER prevent_archived_auto_posting_updates_trigger
          BEFORE UPDATE ON mishka_blog_auto_postings
          FOR EACH ROW
          EXECUTE FUNCTION prevent_archived_auto_posting_updates();
        """

        down "DROP TRIGGER IF EXISTS prevent_archived_auto_posting_updates_trigger ON mishka_blog_auto_postings;"
      end
    end
  end

  # Soft deletion configuration using archived_at timestamp
  archive do
    exclude_read_actions([
      :archived,
      :get_archived,
      :master_get_archived,
      :master_get,
      :master_archived
    ])

    exclude_destroy_actions([:permanent_destroy])
  end

  # Version control configuration for full auto-posting history tracking
  paper_trail do
    primary_key_type(:uuid_v7)
    change_tracking_mode(:snapshot)
    store_action_name?(true)
    store_action_inputs?(true)
    ignore_attributes([:inserted_at, :updated_at, :archived_at])
    ignore_actions([:unarchive, :permanent_destroy])
    attributes_as_attributes([:site_id])
    create_version_on_destroy?(true)
    only_when_changed?(true)
    relationship_opts(public?: true)

    mixin({AshSqlDeb.Mixins.AutoPostingPaperTrailMixin, :postgres, []})
  end

  json_api do
    type "auto_posting"
  end

  actions do
    defaults [:read]

    default_accept @admin_fields

    create :create do
      primary? true
      accept List.delete(@admin_fields, :site_id)

      validate present([:name, :plugin])
      validate {Validations.TenantContext, require_master: false}

      change &Ash.Changeset.force_change_attribute(&1, :site_id, &2.tenant)

      description "Creates auto-posting configuration for tenant users - requires tenant context, auto-assigns site_id"
    end

    create :master_create do
      validate present([:name, :plugin, :site_id])
      validate {Validations.TenantContext, require_master: true}

      change fn changeset, _context ->
        site_id = Ash.Changeset.get_attribute(changeset, :site_id)
        Ash.Changeset.set_tenant(changeset, site_id)
      end

      description "Creates auto-posting configuration for master users - bypasses multi-tenancy, requires explicit site_id"
    end

    update :update do
      primary? true
      require_atomic? false
      transaction? true
      accept List.delete(@admin_fields, :site_id)

      validate {Validations.TenantContext, require_master: false}

      validate absent(:archived_at) do
        message "Cannot edit archived auto-posting configuration. Please unarchive it first."
      end

      description "Updates auto-posting configuration for tenant users - requires tenant context, prevents site_id changes"
    end

    action :master_update, :struct do
      description "Updates auto-posting configuration for master users - requires nil tenant context, prevents site_id changes"
      constraints instance_of: AshSqlDeb.MishkaBlog.AutoPosting

      argument :id, :uuid, allow_nil?: false
      argument :name, :string
      argument :plugin, :string
      argument :description, :string
      argument :is_active, :boolean
      argument :config, :map

      validate {Validations.TenantContext, require_master: true}

      run fn input, _context ->
        id = input.arguments.id

        case Ash.get(AshSqlDeb.MishkaBlog.AutoPosting, id,
               action: :master_get,
               authorize?: false
             ) do
          {:ok, record} when not is_nil(record) ->
            tenant = record.site_id

            attrs =
              input.arguments
              |> Map.delete(:id)
              |> Enum.reject(fn {_k, v} -> is_nil(v) end)
              |> Map.new()

            record
            |> Ash.Changeset.for_update(:update, attrs, tenant: tenant, authorize?: false)
            |> Ash.update()

          _ ->
            {:error,
             Ash.Error.Query.NotFound.exception(resource: AshSqlDeb.MishkaBlog.AutoPosting)}
        end
      end
    end

    read :by_plugin do
      description "Reads auto-posting configuration by plugin within current tenant context"
      argument :plugin, :string, allow_nil?: false
      filter expr(plugin == ^arg(:plugin))
      get? true
      validate {Validations.TenantContext, require_master: false}
    end

    read :master_by_plugin do
      multitenancy :bypass
      description "Reads auto-posting configuration by plugin system-wide (master users only)"
      argument :plugin, :string, allow_nil?: false
      filter expr(plugin == ^arg(:plugin))
      get? true
      validate {Validations.TenantContext, require_master: true}
    end

    read :active do
      description "Reads active auto-posting configurations"
      filter expr(is_active == true)
      pagination offset?: true, default_limit: 20, max_page_size: 100, countable: true
      validate {Validations.TenantContext, require_master: false}
    end

    read :master_active do
      multitenancy :bypass
      description "Reads active auto-posting configurations system-wide (master users only)"
      filter expr(is_active == true)
      pagination offset?: true, default_limit: 20, max_page_size: 100, countable: true
      validate {Validations.TenantContext, require_master: true}
    end

    read :master_read do
      description "Reads all auto-posting configurations system-wide, bypassing tenant filtering (master users only)"
      multitenancy :bypass
      pagination offset?: true, default_limit: 20, max_page_size: 100, countable: true
      validate {Validations.TenantContext, require_master: true}
    end

    read :master_get do
      multitenancy :bypass
      get? true
      description "Retrieves single auto-posting configuration by ID, bypassing tenant filtering"
    end

    read :archived do
      filter expr(not is_nil(archived_at))
      pagination offset?: true, default_limit: 20, max_page_size: 100, countable: true
      validate {Validations.TenantContext, require_master: false}
      description "Lists archived auto-posting configurations within current tenant context"
    end

    read :get_archived do
      get? true
      filter expr(not is_nil(archived_at))
      validate {Validations.TenantContext, require_master: false}

      description "Retrieves single archived auto-posting configuration for recovery or inspection (tenant users)"
    end

    read :master_get_archived do
      get? true
      multitenancy :bypass
      filter expr(not is_nil(archived_at))
      validate {Validations.TenantContext, require_master: false}

      description "Retrieves single archived auto-posting configuration for recovery or inspection (master users)"
    end

    read :master_archived do
      multitenancy :bypass
      filter expr(not is_nil(archived_at))
      pagination offset?: true, default_limit: 20, max_page_size: 100, countable: true
      validate {Validations.TenantContext, require_master: true}

      description "Lists all archived auto-posting configurations system-wide, bypassing tenant filtering"
    end

    update :activate do
      accept []
      require_atomic? false

      validate {Validations.TenantContext, require_master: false}

      change set_attribute(:is_active, true)

      description "Activates an auto-posting configuration"
    end

    action :master_activate, :struct do
      description "Activates an auto-posting configuration (master users)"
      constraints instance_of: AshSqlDeb.MishkaBlog.AutoPosting
      argument :id, :uuid, allow_nil?: false

      validate {Validations.TenantContext, require_master: true}

      run fn input, _context ->
        id = input.arguments.id

        case Ash.get(AshSqlDeb.MishkaBlog.AutoPosting, id,
               action: :master_get,
               authorize?: false
             ) do
          {:ok, record} when not is_nil(record) ->
            tenant = record.site_id

            record
            |> Ash.Changeset.for_update(:activate, %{}, tenant: tenant, authorize?: false)
            |> Ash.update()

          _ ->
            {:error,
             Ash.Error.Query.NotFound.exception(resource: AshSqlDeb.MishkaBlog.AutoPosting)}
        end
      end
    end

    update :deactivate do
      accept []
      require_atomic? false

      validate {Validations.TenantContext, require_master: false}

      change set_attribute(:is_active, false)

      description "Deactivates an auto-posting configuration"
    end

    action :master_deactivate, :struct do
      description "Deactivates an auto-posting configuration (master users)"
      constraints instance_of: AshSqlDeb.MishkaBlog.AutoPosting
      argument :id, :uuid, allow_nil?: false

      validate {Validations.TenantContext, require_master: true}

      run fn input, _context ->
        id = input.arguments.id

        case Ash.get(AshSqlDeb.MishkaBlog.AutoPosting, id,
               action: :master_get,
               authorize?: false
             ) do
          {:ok, record} when not is_nil(record) ->
            tenant = record.site_id

            record
            |> Ash.Changeset.for_update(:deactivate, %{}, tenant: tenant, authorize?: false)
            |> Ash.update()

          _ ->
            {:error,
             Ash.Error.Query.NotFound.exception(resource: AshSqlDeb.MishkaBlog.AutoPosting)}
        end
      end
    end

    destroy :destroy do
      description "Soft deletes auto-posting configuration by archiving (tenant users)"
      primary? true
      require_atomic? false

      validate {Validations.TenantContext, require_master: false}

      validate fn changeset, _context ->
        if changeset.data.archived_at do
          {:error, field: :archived_at, message: "Auto-posting configuration is already archived"}
        else
          :ok
        end
      end
    end

    action :master_destroy, :struct do
      description "Soft deletes auto-posting configuration by archiving (master users) - requires nil tenant context"
      constraints instance_of: AshSqlDeb.MishkaBlog.AutoPosting
      argument :id, :uuid, allow_nil?: false

      validate {Validations.TenantContext, require_master: true}

      run fn input, _context ->
        id = input.arguments.id

        Ash.get(AshSqlDeb.MishkaBlog.AutoPosting, id,
          action: :master_get,
          authorize?: false
        )
        |> case do
          {:ok, record} when not is_nil(record) ->
            tenant = record.site_id

            record
            |> Ash.Changeset.for_destroy(:destroy, %{}, tenant: tenant, authorize?: false)
            |> Ash.destroy(return_destroyed?: true)

          _ ->
            {:error,
             Ash.Error.Query.NotFound.exception(resource: AshSqlDeb.MishkaBlog.AutoPosting)}
        end
      end
    end

    update :unarchive do
      accept []
      require_atomic? false

      validate {Validations.TenantContext, require_master: false}

      change set_attribute(:archived_at, nil)

      atomic_upgrade_with :archived

      description "Restores archived auto-posting configuration (tenant users)"
    end

    action :master_unarchive, :struct do
      description "Restores archived auto-posting configuration (master users) - requires nil tenant context"
      constraints instance_of: AshSqlDeb.MishkaBlog.AutoPosting
      argument :id, :uuid, allow_nil?: false

      validate {Validations.TenantContext, require_master: true}

      run fn input, _context ->
        id = input.arguments.id

        Ash.get(AshSqlDeb.MishkaBlog.AutoPosting, id,
          action: :master_get,
          authorize?: false
        )
        |> case do
          {:ok, record} when not is_nil(record) ->
            if is_nil(record.archived_at) do
              {:error,
               Ash.Error.Invalid.exception(
                 errors: [
                   Ash.Error.Changes.InvalidAttribute.exception(
                     field: :archived_at,
                     message: "Auto-posting configuration is not archived"
                   )
                 ]
               )}
            else
              tenant = record.site_id

              record
              |> Ash.Changeset.for_update(:unarchive, %{}, tenant: tenant, authorize?: false)
              |> Ash.update()
            end

          _ ->
            {:error,
             Ash.Error.Query.NotFound.exception(resource: AshSqlDeb.MishkaBlog.AutoPosting)}
        end
      end
    end

    destroy :permanent_destroy do
      require_atomic? false
      validate {Validations.TenantContext, require_master: false}

      description "Permanently removes auto-posting configuration and version history from database (tenant users) - use with extreme caution"
    end

    action :master_permanent_destroy, :struct do
      description "Permanently removes auto-posting configuration and version history from database (master users) - irreversible and extremely dangerous"
      constraints instance_of: AshSqlDeb.MishkaBlog.AutoPosting
      argument :id, :uuid, allow_nil?: false

      validate {Validations.TenantContext, require_master: true}

      run fn input, _context ->
        id = input.arguments.id

        Ash.get(AshSqlDeb.MishkaBlog.AutoPosting, id,
          action: :master_get,
          authorize?: false
        )
        |> case do
          {:ok, record} when not is_nil(record) ->
            tenant = record.site_id

            record
            |> Ash.Changeset.for_destroy(:permanent_destroy, %{},
              tenant: tenant,
              authorize?: false
            )
            |> Ash.destroy()

            {:ok, record}

          _ ->
            {:error,
             Ash.Error.Query.NotFound.exception(resource: AshSqlDeb.MishkaBlog.AutoPosting)}
        end
      end
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  # Multi-tenancy configuration - auto-posting configurations are always site-specific
  multitenancy do
    strategy :attribute
    attribute :site_id
    # Auto-posting configurations are NEVER global - always site-specific
    global? false
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 255, trim?: true
      description "Name of the auto-posting configuration"
    end

    attribute :plugin, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 255, trim?: true
      description "Plugin identifier (unique per site)"
    end

    attribute :description, :string do
      allow_nil? true
      public? true
      description "Description of what this auto-posting configuration does"
    end

    attribute :is_active, :boolean do
      default false
      public? true
      description "Whether this auto-posting configuration is enabled"
    end

    attribute :config, :map do
      allow_nil? true
      public? true
      default %{}

      description "Plugin-specific configuration as key-value pairs with metadata (field type, value, help text)"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :site, AshSqlDeb.Runtime.Site do
      allow_nil? false
      public? true
      description "The site this auto-posting configuration belongs to"
    end
  end

  identities do
    identity :unique_plugin_per_site, [:plugin, :site_id] do
      description "Ensures each plugin has only one configuration per site"
      message "This plugin already has a configuration for this site"
      all_tenants? true
      nils_distinct? false
    end
  end
end
