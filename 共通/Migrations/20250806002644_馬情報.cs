// 役割: 馬情報テーブル追加時のEF Coreマイグレーションです。
// 既存DBへ適用する際のUp/Down処理を保持しています。
using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace 共通.Migrations
{
    /// <inheritdoc />
    public partial class 馬情報 : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {

            migrationBuilder.CreateTable(
                name: "馬情報",
                columns: table => new
                {
                    Id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    馬名 = table.Column<string>(type: "nvarchar(9)", maxLength: 9, nullable: false),
                    生年月日 = table.Column<DateOnly>(type: "date", nullable: false),
                    性別 = table.Column<string>(type: "nvarchar(2)", maxLength: 2, nullable: false),
                    毛色 = table.Column<string>(type: "nvarchar(4)", maxLength: 4, nullable: false),
                    産地 = table.Column<string>(type: "nvarchar(16)", maxLength: 16, nullable: false),
                    調教師 = table.Column<string>(type: "nvarchar(10)", maxLength: 10, nullable: false),
                    所属 = table.Column<string>(type: "nvarchar(6)", maxLength: 6, nullable: false),
                    馬主 = table.Column<string>(type: "nvarchar(32)", maxLength: 32, nullable: false),
                    生産牧場 = table.Column<string>(type: "nvarchar(32)", maxLength: 32, nullable: false),
                    地方収得賞金 = table.Column<int>(type: "int", nullable: false),
                    中央収得賞金 = table.Column<int>(type: "int", nullable: false),
                    中央付加賞金 = table.Column<int>(type: "int", nullable: false),
                    父 = table.Column<string>(type: "nvarchar(18)", maxLength: 18, nullable: false),
                    父父 = table.Column<string>(type: "nvarchar(18)", maxLength: 18, nullable: false),
                    父母 = table.Column<string>(type: "nvarchar(18)", maxLength: 18, nullable: false),
                    母 = table.Column<string>(type: "nvarchar(18)", maxLength: 18, nullable: false),
                    母父 = table.Column<string>(type: "nvarchar(18)", maxLength: 18, nullable: false),
                    母母 = table.Column<string>(type: "nvarchar(18)", maxLength: 18, nullable: false),
                    更新日 = table.Column<DateOnly>(type: "date", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_馬情報", x => x.Id);
                });
            migrationBuilder.CreateIndex(
                name: "IX_調教師",
                table: "馬情報",
                column: "調教師");

            migrationBuilder.CreateIndex(
                name: "IX_馬主",
                table: "馬情報",
                column: "馬主");

            migrationBuilder.CreateIndex(
                name: "IX_馬名",
                table: "馬情報",
                column: "馬名",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_馬名_更新日",
                table: "馬情報",
                columns: new[] { "馬名", "更新日" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_馬名_生年月日_父",
                table: "馬情報",
                columns: new[] { "馬名", "生年月日", "父" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {

            migrationBuilder.DropTable(
                name: "馬情報");
        }
    }
}
