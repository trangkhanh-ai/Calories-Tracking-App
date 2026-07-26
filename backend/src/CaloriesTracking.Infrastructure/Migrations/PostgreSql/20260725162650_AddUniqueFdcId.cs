using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace CaloriesTracking.Infrastructure.Migrations.PostgreSql
{
    /// <inheritdoc />
    public partial class AddUniqueFdcId : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(
                """
                DO $$
                DECLARE conflict_count integer;
                BEGIN
                    SELECT COUNT(*) INTO conflict_count FROM (
                        SELECT "FdcId"
                        FROM "Foods"
                        WHERE "FdcId" IS NOT NULL
                        GROUP BY "FdcId"
                        HAVING COUNT(*) > 1
                    ) duplicates;

                    IF conflict_count > 0 THEN
                        RAISE EXCEPTION
                            'Migration blocked: % duplicate non-null FdcId value(s) exist in Foods. Resolve them manually before upgrading.',
                            conflict_count;
                    END IF;
                END $$;
                """);

            migrationBuilder.CreateIndex(
                name: "IX_Foods_FdcId",
                table: "Foods",
                column: "FdcId",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_Foods_FdcId",
                table: "Foods");
        }
    }
}
