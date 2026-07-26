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
