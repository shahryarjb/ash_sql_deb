defmodule AshSqlDeb.Mixins.AutoPostingPaperTrailMixin do
  def postgres do
    quote do
      postgres do
        table "auto_posting_versions"
        repo AshSqlDeb.Repo

        references do
          reference :version_source, on_delete: :delete
        end
      end

      actions do
        read :get_any do
          get? true
        end

        read :read_any do
        end
      end
    end
  end
end
