using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace CaloriesTracking.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddUserActivityLevel : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "ActivityLevel",
                table: "Users",
                type: "TEXT",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "ActivityLevel",
                table: "Users");
        }
    }
}
