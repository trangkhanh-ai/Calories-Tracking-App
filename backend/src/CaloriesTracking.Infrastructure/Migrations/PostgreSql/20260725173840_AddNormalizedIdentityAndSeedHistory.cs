using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace CaloriesTracking.Infrastructure.Migrations.PostgreSql
{
    /// <inheritdoc />
    public partial class AddNormalizedIdentityAndSeedHistory : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_Foods_FdcId",
                table: "Foods");

            migrationBuilder.AddColumn<string>(
                name: "NormalizedEmail",
                table: "Users",
                type: "character varying(254)",
                maxLength: 254,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<string>(
                name: "NormalizedUsername",
                table: "Users",
                type: "character varying(100)",
                maxLength: 100,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<string>(
                name: "NormalizedName",
                table: "Foods",
                type: "character varying(200)",
                maxLength: 200,
                nullable: false,
                defaultValue: "");

            migrationBuilder.CreateTable(
                name: "SeedHistories",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    Name = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    Version = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    Status = table.Column<int>(type: "integer", nullable: false),
                    StartedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    CompletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    ProcessedRows = table.Column<int>(type: "integer", nullable: false),
                    TotalRows = table.Column<int>(type: "integer", nullable: true),
                    LastProcessedSourceRow = table.Column<int>(type: "integer", nullable: false),
                    ErrorSummary = table.Column<string>(type: "character varying(1024)", maxLength: 1024, nullable: true),
                    LockOwner = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    LockExpiresAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_SeedHistories", x => x.Id);
                });

            // Backfill BEFORE the unique indexes below. Without this every
            // existing row would carry the empty-string default and the second
            // row would collide immediately.
            migrationBuilder.Sql(
                """
                UPDATE "Users"
                SET "NormalizedUsername" = UPPER(BTRIM("Username")),
                    "NormalizedEmail"    = UPPER(BTRIM("Email"));
                """);

            migrationBuilder.Sql(
                """
                UPDATE "Foods"
                SET "NormalizedName" = UPPER(BTRIM("Name"));
                """);

            // Rows differing only by case would otherwise fail the unique index
            // with an opaque provider error. Raise a named, actionable message
            // instead. Conflicting accounts are never merged or deleted — that
            // is an operator decision.
            migrationBuilder.Sql(
                """
                DO $$
                DECLARE conflict_count integer;
                BEGIN
                    SELECT COUNT(*) INTO conflict_count FROM (
                        SELECT "NormalizedUsername"
                        FROM "Users"
                        GROUP BY "NormalizedUsername"
                        HAVING COUNT(*) > 1
                    ) duplicates;

                    IF conflict_count > 0 THEN
                        RAISE EXCEPTION
                            'Migration blocked: % case-insensitive duplicate username(s) exist in Users. Resolve them manually before upgrading.',
                            conflict_count;
                    END IF;

                    SELECT COUNT(*) INTO conflict_count FROM (
                        SELECT "NormalizedEmail"
                        FROM "Users"
                        GROUP BY "NormalizedEmail"
                        HAVING COUNT(*) > 1
                    ) duplicates;

                    IF conflict_count > 0 THEN
                        RAISE EXCEPTION
                            'Migration blocked: % case-insensitive duplicate email(s) exist in Users. Resolve them manually before upgrading.',
                            conflict_count;
                    END IF;
                END $$;
                """);

            migrationBuilder.CreateIndex(
                name: "IX_Users_NormalizedEmail",
                table: "Users",
                column: "NormalizedEmail",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Users_NormalizedUsername",
                table: "Users",
                column: "NormalizedUsername",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Foods_FdcId",
                table: "Foods",
                column: "FdcId",
                unique: true,
                filter: "\"FdcId\" IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "IX_Foods_NormalizedName_Custom",
                table: "Foods",
                column: "NormalizedName",
                unique: true,
                filter: "\"FdcId\" IS NULL");

            migrationBuilder.CreateIndex(
                name: "IX_SeedHistories_Name_Version",
                table: "SeedHistories",
                columns: new[] { "Name", "Version" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "SeedHistories");

            migrationBuilder.DropIndex(
                name: "IX_Users_NormalizedEmail",
                table: "Users");

            migrationBuilder.DropIndex(
                name: "IX_Users_NormalizedUsername",
                table: "Users");

            migrationBuilder.DropIndex(
                name: "IX_Foods_FdcId",
                table: "Foods");

            migrationBuilder.DropIndex(
                name: "IX_Foods_NormalizedName_Custom",
                table: "Foods");

            migrationBuilder.DropColumn(
                name: "NormalizedEmail",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "NormalizedUsername",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "NormalizedName",
                table: "Foods");

            migrationBuilder.CreateIndex(
                name: "IX_Foods_FdcId",
                table: "Foods",
                column: "FdcId",
                unique: true);
        }
    }
}
