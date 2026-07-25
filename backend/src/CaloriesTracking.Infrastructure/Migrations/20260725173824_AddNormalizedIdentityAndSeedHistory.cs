using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace CaloriesTracking.Infrastructure.Migrations
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
                type: "TEXT",
                maxLength: 254,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<string>(
                name: "NormalizedUsername",
                table: "Users",
                type: "TEXT",
                maxLength: 100,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<string>(
                name: "NormalizedName",
                table: "Foods",
                type: "TEXT",
                maxLength: 200,
                nullable: false,
                defaultValue: "");

            migrationBuilder.CreateTable(
                name: "SeedHistories",
                columns: table => new
                {
                    Id = table.Column<int>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlite:Autoincrement", true),
                    Name = table.Column<string>(type: "TEXT", maxLength: 100, nullable: false),
                    Version = table.Column<string>(type: "TEXT", maxLength: 50, nullable: false),
                    Status = table.Column<int>(type: "INTEGER", nullable: false),
                    StartedAt = table.Column<DateTime>(type: "TEXT", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "TEXT", nullable: false),
                    CompletedAt = table.Column<DateTime>(type: "TEXT", nullable: true),
                    ProcessedRows = table.Column<int>(type: "INTEGER", nullable: false),
                    TotalRows = table.Column<int>(type: "INTEGER", nullable: true),
                    LastProcessedSourceRow = table.Column<int>(type: "INTEGER", nullable: false),
                    ErrorSummary = table.Column<string>(type: "TEXT", maxLength: 1024, nullable: true),
                    LockOwner = table.Column<string>(type: "TEXT", maxLength: 100, nullable: true),
                    LockExpiresAt = table.Column<DateTime>(type: "TEXT", nullable: true)
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
                SET "NormalizedUsername" = UPPER(TRIM("Username")),
                    "NormalizedEmail"    = UPPER(TRIM("Email"));
                """);

            migrationBuilder.Sql(
                """
                UPDATE "Foods"
                SET "NormalizedName" = UPPER(TRIM("Name"));
                """);

            // Rows differing only by case would make the unique indexes below
            // fail with an opaque provider error. MigrationPreflight.
            // EnsureNoCaseInsensitiveUserConflictsAsync runs before MigrateAsync
            // and reports those conflicts by name; the indexes here are the hard
            // backstop. Conflicting accounts are never merged or deleted —
            // that is an operator decision.
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
