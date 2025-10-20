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

  resources do
    resource AshSqlDeb.MishkaBlog.AutoPosting
  end
end
