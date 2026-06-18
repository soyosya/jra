// 役割: 楽天/極ウマ等の資格情報を git追跡外の secrets.local.json から読みます。
// 解決順: secrets.local.json(キー値) → 環境変数。ファイルは AppContext.BaseDirectory から上位を遡って探索。
// secrets.local.json は .gitignore 済み(コミット禁止)。テンプレは secrets.local.example.json。
using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;

namespace 中央競馬.共通.Libraly
{
    /// <summary>git追跡外のローカル資格情報(secrets.local.json)を読むヘルパー。</summary>
    public static class Secrets
    {
        private static readonly Dictionary<string, string> _v = Load();

        private static Dictionary<string, string> Load()
        {
            var d = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            try
            {
                foreach (var path in CandidatePaths())
                {
                    if (!File.Exists(path)) continue;
                    using var doc = JsonDocument.Parse(File.ReadAllText(path));
                    foreach (var p in doc.RootElement.EnumerateObject())
                        if (p.Value.ValueKind == JsonValueKind.String)
                            d[p.Name] = p.Value.GetString() ?? "";
                    break;  // 最初に見つかったファイルを採用
                }
            }
            catch { /* 壊れた/無い場合は環境変数フォールバックに任せる */ }
            return d;
        }

        // 実行ディレクトリから上位(リポジトリ直下など)へ最大8階層、secrets.local.json を探す。
        private static IEnumerable<string> CandidatePaths()
        {
            var dir = new DirectoryInfo(AppContext.BaseDirectory);
            for (int i = 0; i < 8 && dir != null; i++)
            {
                yield return Path.Combine(dir.FullName, "secrets.local.json");
                dir = dir.Parent;
            }
        }

        /// <summary>キー値(secrets.local.json) → 環境変数 の順で取得。どちらも無ければ null。</summary>
        public static string? Get(string key, string? envVar = null)
        {
            if (_v.TryGetValue(key, out var v) && !string.IsNullOrWhiteSpace(v)) return v;
            if (envVar != null)
            {
                var e = Environment.GetEnvironmentVariable(envVar);
                if (!string.IsNullOrWhiteSpace(e)) return e;
            }
            return null;
        }

        public static string? RakutenUser => Get("RakutenUser", "RAKUTEN_USER");
        public static string? RakutenPass => Get("RakutenPass", "RAKUTEN_PASS");
        public static string? RakutenPin => Get("RakutenPin", "RAKUTEN_PIN");
        public static string? GokuUmaUser => Get("GokuUmaUser", "GOKUUMA_USER");
        public static string? GokuUmaPass => Get("GokuUmaPass", "GOKUUMA_PASS");
    }
}
