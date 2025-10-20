defmodule AshSqlDeb.MishkaBlog.Resources.Validations.TenantContext do
  @moduledoc """
  Enforces tenant context requirements for blog resource operations.

  This validation ensures that actions are called with the correct tenant context
  based on whether they are intended for master users or tenant users. It provides
  a flexible way to validate tenant context requirements across different actions.

  ## Options

  - `:require_master` - Boolean flag indicating the expected context:
    - `true`: Requires context.tenant to be nil (master user operation)
    - `false`: Requires context.tenant to be present (tenant user operation)

  ## Behavior

  - When `authorize?: false`, the validation is bypassed to allow system operations
  - For master operations (`require_master: true`), validates that `context.tenant` is nil
  - For tenant operations (`require_master: false`), validates that `context.tenant` is present

  ## Usage Examples

      # In a master-only create action
      create :master_create do
        validate {MishkaBlog.Resources.Validations.TenantContext, require_master: true}
      end

      # In a tenant-only create action
      create :create do
        validate {MishkaBlog.Resources.Validations.TenantContext, require_master: false}
      end

      # In a master-only read action
      read :master_read do
        validate {MishkaBlog.Resources.Validations.TenantContext, require_master: true}
      end

      # In a generic action
      action :master_update, :struct do
        validate {MishkaBlog.Resources.Validations.TenantContext, require_master: true}
      end

  ## Error Messages

  The validation provides clear error messages guiding users to the appropriate action:
  - For master operations: "Tenant context must be nil for this action. Use the tenant action instead."
  - For tenant operations: "Tenant context is required for this action. Use the master action instead."
  """
  use Ash.Resource.Validation

  @impl true
  @doc """
  Initializes the validation with provided options.

  ## Parameters
  - `opts` - Keyword list containing:
    - `:require_master` - Boolean indicating if master context is required

  ## Returns
  - `{:ok, opts}` with validated options
  """
  def init(opts) do
    require_master = Keyword.get(opts, :require_master)

    if is_nil(require_master) do
      raise ArgumentError, "TenantContext validation requires :require_master option (true/false)"
    end

    if !is_boolean(require_master) do
      raise ArgumentError,
            ":require_master option must be a boolean, got: #{inspect(require_master)}"
    end

    {:ok, opts}
  end

  @impl true
  @doc """
  Validates tenant context based on the action requirements.

  ## Parameters
  - `subject` - The Ash changeset or action input being validated
  - `opts` - Validation options containing :require_master flag
  - `context` - Context containing tenant and authorization information

  ## Returns
  - `:ok` if validation passes
  - `{:error, message: String.t()}` if validation fails
  """
  def validate(_subject, _opts, %{authorize?: false}), do: :ok

  def validate(_subject, opts, context) do
    require_master = Keyword.get(opts, :require_master)
    tenant = context.tenant

    cond do
      # Master action requires nil tenant
      require_master and not is_nil(tenant) ->
        {:error,
         message: "Tenant context must be nil for this action. Use the tenant action instead."}

      # Tenant action requires non-nil tenant
      not require_master and is_nil(tenant) ->
        {:error,
         message: "Tenant context is required for this action. Use the master action instead."}

      # Valid configuration
      true ->
        :ok
    end
  end

  @impl true
  def atomic(_opts, _context, _actor), do: :ok

  @impl true
  def has_validate?(), do: true

  @impl true
  def supports(_opts), do: [Ash.Changeset, Ash.ActionInput, Ash.Query]
end
