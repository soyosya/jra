namespace 中央競馬.IpatVote;

/// <summary>方式名の解析(式別ごとに名称・DOMが異なるながし方式を統一的に判定)。
/// 三連複: 軸1頭ながし/軸2頭ながし。三連単: 1着/2着/3着/1・2着/1・3着/2・3着ながし。</summary>
public static class MethodParse
{
    /// <summary>三連複ながしの軸頭数(軸2頭=2、それ以外=1)。</summary>
    public static int TrioAxisCount(string m)
        => ((m ?? "").Contains("２頭") || (m ?? "").Contains("2頭") || (m ?? "").Contains("二頭")) ? 2 : 1;

    /// <summary>三連単着ながしの固定着順(1着/2着/3着)。名称中の数字で判定。既定[1]。
    /// 例: 「１・２着ながし」→[1,2]、「２・３着ながし」→[2,3]、「１着ながし」→[1]。</summary>
    public static List<int> TrifectaFixedPos(string m)
    {
        m ??= ""; var s = new List<int>();
        if (m.Contains('1') || m.Contains('１') || m.Contains('一')) s.Add(1);
        if (m.Contains('2') || m.Contains('２') || m.Contains('二')) s.Add(2);
        if (m.Contains('3') || m.Contains('３') || m.Contains('三')) s.Add(3);
        if (s.Count == 0) s.Add(1);
        return s;
    }
}

/// <summary>点数計算(式別×方式×相手数)。全式別×全方式対応。
/// 規約: ボックスは {軸(あれば)}∪相手 を箱馬とみなす(N頭)。ながしは相手数P。マルチは馬単×2/三連単×3。
/// フォーメーションは f1/f2/f3 列を実列挙(重複・同一馬を除外)。</summary>
public static class Points
{
    static List<int> Nums(IEnumerable<string> xs)
        => xs.Select(s => int.TryParse((s ?? "").Trim(), out var v) ? v : -1).Where(v => v > 0).Distinct().ToList();

    public static int ForTicket(BetTicket b, IpatOptions opt)
    {
        var bt = string.IsNullOrWhiteSpace(b.BetType) ? opt.BetType : b.BetType;
        var mh = string.IsNullOrWhiteSpace(b.Method) ? opt.Method : b.Method;
        if (!string.IsNullOrWhiteSpace(b.Kumiban)) return 1; // 確定組番の1点
        if (bt is "単勝" or "複勝") return 1;

        bool isBox = mh.Contains("ボックス") || mh.Contains("box", StringComparison.OrdinalIgnoreCase);
        bool isForm = mh.Contains("フォーメーション") || mh.Contains("formation", StringComparison.OrdinalIgnoreCase);
        bool isNagashi = !isBox && !isForm && (mh.Contains("流") || mh.Contains("ながし"));
        bool isMulti = b.Multi || mh.Contains("マルチ");

        if (isForm) return FormationPoints(bt, b.F1, b.F2, b.F3);

        int P = b.Partners.Count > 0 ? b.Partners.Count : opt.PartnerCount;            // ながし相手数
        bool axisValid = int.TryParse((b.AxisUma ?? "").Trim(), out var ax) && ax > 0;
        int N = (axisValid ? 1 : 0) + P;                                              // ボックス箱馬数 {軸}∪相手

        int pts = bt switch
        {
            "枠連" or "馬連" or "ワイド" => isNagashi ? P : isBox ? N * (N - 1) / 2 : 1,
            "馬単" => isNagashi ? P * (isMulti ? 2 : 1) : isBox ? N * (N - 1) : 1,
            // 三連複: 軸1頭ながし=C(P,2) / 軸2頭ながし=P
            "三連複" => isNagashi ? (MethodParse.TrioAxisCount(mh) == 2 ? P : P * (P - 1) / 2) : isBox ? N * (N - 1) * (N - 2) / 6 : 1,
            // 三連単: 1着等の単独固定ながし=P*(P-1)(マルチ×3) / 1・2着等の2着固定ながし=P(マルチ×6=3!)
            "三連単" => isNagashi
                ? (MethodParse.TrifectaFixedPos(mh).Count == 2 ? P * (isMulti ? 6 : 1) : P * (P - 1) * (isMulti ? 3 : 1))
                : isBox ? N * (N - 1) * (N - 2) : 1,
            _ => 1
        };
        return Math.Max(1, pts);
    }

    /// <summary>フォーメーション点数を実列挙(同一馬を含む組を除外し重複排除)。</summary>
    static int FormationPoints(string bt, List<string> f1, List<string> f2, List<string> f3)
    {
        var a = Nums(f1); var c2 = Nums(f2); var c3 = Nums(f3);
        var set = new HashSet<string>();
        if (bt is "枠連" or "馬連" or "ワイド") // 無順2列
            foreach (var x in a) foreach (var y in c2) { if (x == y) continue; set.Add(Math.Min(x, y) + "-" + Math.Max(x, y)); }
        else if (bt == "馬単") // 有順2列(1着→2着)
            foreach (var x in a) foreach (var y in c2) { if (x == y) continue; set.Add(x + "-" + y); }
        else if (bt == "三連複") // 無順3列
            foreach (var x in a) foreach (var y in c2) foreach (var z in c3) { if (x == y || y == z || x == z) continue; var s = new[] { x, y, z }; Array.Sort(s); set.Add(string.Join("-", s)); }
        else if (bt == "三連単") // 有順3列(1→2→3着)
            foreach (var x in a) foreach (var y in c2) foreach (var z in c3) { if (x == y || y == z || x == z) continue; set.Add(x + "-" + y + "-" + z); }
        return Math.Max(set.Count, 1);
    }
}

/// <summary>投票フォーム操作(通常投票 AngularJS #!/bet/basic、較正済2026-06-21)。三連複は方式=通常の単一チェック列にC(相手,2)組を展開(=軸1頭流しと等価)。ConfirmStopは合計金額入力直前で停止(人が最終操作)。</summary>
public sealed class BettingPage
{
    readonly IpatOptions _opt; readonly IpatSession _sess;
    public BettingPage(IpatOptions opt, IpatSession sess) { _opt = opt; _sess = sess; }

    static bool IsTodo(string s) => string.IsNullOrWhiteSpace(s) || s.StartsWith("TODO_");

    // IPATの式別<select>の可視テキスト(３連複/３連単は全角３)。
    static string BetTypeText(string bt) => bt switch
    {
        "単勝" => "単勝", "複勝" => "複勝", "枠連" => "枠連", "馬連" => "馬連",
        "ワイド" => "ワイド", "馬単" => "馬単",
        "三連複" or "3連複" or "３連複" => "３連複",
        "三連単" or "3連単" or "３連単" => "３連単",
        _ => bt
    };

    string Chk(int uma) => _opt.Selectors.AxisInputTemplate.Replace("{UMA}", uma.ToString());   // 単一チェック列 input#no{n}
    // 位置別列(1着/軸=col1, 2着/相手=col2, 3着=col3)。IPAT通常投票は horse{k}_no{n} で統一。
    string H(int col, int uma) => (col switch
    {
        1 => _opt.Selectors.NagashiAxisTemplate,
        2 => _opt.Selectors.NagashiPartnerTemplate,
        _ => _opt.Selectors.Pos3Template
    }).Replace("{UMA}", uma.ToString());

    static string Zen(int d) => d switch { 1 => "１", 2 => "２", 3 => "３", _ => "１" };
    // 三連単着ながしの方式select可視テキスト([1]→「１着ながし」/[1,2]→「１・２着ながし」)
    static string TrifectaMethodText(List<int> pos) => string.Join("・", pos.Select(Zen)) + "着ながし";
    static int NagashiPos(string m) // 着ながしの軸位置(既定1)
    {
        m ??= "";
        if (m.Contains("3") || m.Contains("３") || m.Contains("三")) return 3;
        if (m.Contains("2") || m.Contains("２") || m.Contains("二")) return 2;
        return 1;
    }

    static List<int> Nums(IEnumerable<string> xs)
        => xs.Select(s => int.TryParse((s ?? "").Trim(), out var v) ? v : -1).Where(v => v > 0).ToList();

    public BetResult PlaceBet(BetTicket b, out int spent)
    {
        int pts = Points.ForTicket(b, _opt);
        int unit = b.StakeYen > 0 ? Math.Max(100, b.StakeYen / 100 * 100) : _opt.StakePerPointYen;
        spent = pts * unit;

        if (_opt.ResolvedMode == BetMode.DryRun) return BetResult.Planned; // 無投票プレビュー

        // --- ここから実投票(ConfirmStop/Auto) ---
        if (IsTodo(_opt.Selectors.SelRacecourse) || IsTodo(_opt.Selectors.PurchaseButton) || IsTodo(_opt.Selectors.AmountInput))
        {
            Log.Line($"  【未較正】投票フォームのセレクタがプレースホルダ。{b.Venue}{b.Race}Rは投票せず中断。ipat.json Selectorsを較正してください。");
            return BetResult.Failed;
        }

        var bt = string.IsNullOrWhiteSpace(b.BetType) ? _opt.BetType : b.BetType;
        var mh = string.IsNullOrWhiteSpace(b.Method) ? _opt.Method : b.Method;
        if (bt is not ("単勝" or "複勝" or "枠連" or "馬連" or "ワイド" or "馬単" or "三連複" or "三連単"))
        {
            Log.Line($"  【未対応式別】{bt}({b.Venue}{b.Race}R)。中断。");
            return BetResult.Failed;
        }

        // 方式の判定
        bool isBox = mh.Contains("ボックス") || mh.Contains("box", StringComparison.OrdinalIgnoreCase);
        bool isForm = mh.Contains("フォーメーション") || mh.Contains("formation", StringComparison.OrdinalIgnoreCase);
        bool isNagashi = !isBox && !isForm && (mh.Contains("流") || mh.Contains("ながし"));
        bool isMulti = b.Multi || mh.Contains("マルチ");
        bool positional = bt is "馬単" or "三連単";                 // 着順固定(horse{k}_no)
        int legs = bt is "三連複" or "三連単" ? 3 : bt is "枠連" or "馬連" or "ワイド" or "馬単" ? 2 : 1;

        // 方式select用テキスト(式別で名称が異なる: 三連複=「軸１頭ながし」、馬単/三連単=「N着ながし」、馬連/ワイド/枠連=「ながし」)
        string methodText;
        if (bt is "単勝" or "複勝") methodText = "";
        else if (isBox) methodText = "ボックス";
        else if (isForm) methodText = "フォーメーション";
        else if (isNagashi)
            methodText = bt == "三連複" ? $"軸{Zen(MethodParse.TrioAxisCount(mh))}頭ながし"  // 軸1頭/軸2頭ながし
                       : bt == "三連単" ? TrifectaMethodText(MethodParse.TrifectaFixedPos(mh)) // 1着/1・2着等
                       : positional ? $"{Zen(NagashiPos(mh))}着ながし"     // 馬単
                       : "ながし";                                         // 馬連/ワイド/枠連
        else methodText = "通常";

        try
        {
            // 1) 通常投票へ → 場/レース選択(プルダウン形式とボタン形式の両対応)
            _sess.TryClick(_opt.Selectors.MenuNormalVote);
            _sess.WaitForExists(".ipat-select-course-race", TimeSpan.FromSeconds(12)); // 場/レース選択域(両レイアウト共通の枠)
            Thread.Sleep(300);
            if (_sess.IsDisplayed(_opt.Selectors.SelRacecourse))
            {   // プルダウン形式: <select>を可視テキスト/値で選択
                _sess.TrySelectOptionContaining(_opt.Selectors.SelRacecourse, b.Venue);       // 「東京」→「東京(日)」
                _sess.TrySelectByValue(_opt.Selectors.SelRaceNumber, (b.Race - 1).ToString()); // option値=raceIndex
            }
            else
            {   // ボタン形式: 場名ボタン→レース番号ボタンをクリック
                if (!_sess.TryClickContaining(".places button", b.Venue))
                { Log.Line($"  場名ボタン({b.Venue})が見つかりません({b.Venue}{b.Race}R)。中断。"); return BetResult.Failed; }
                Thread.Sleep(400); // レース一覧の再描画待ち
                if (!_sess.TryClickRaceButton(".races button", b.Race))
                { Log.Line($"  レースボタン({b.Race}R)が見つかりません/締切({b.Venue}{b.Race}R)。中断。"); return BetResult.Failed; }
            }
            Thread.Sleep(400); // 式別/方式テーブルの描画待ち
            // 式別/方式を選択(両レイアウト共通の<select>)
            _sess.WaitForExists(_opt.Selectors.SelBetType, TimeSpan.FromSeconds(8));
            _sess.TrySelectByText(_opt.Selectors.SelBetType, BetTypeText(bt));
            Thread.Sleep(300); // 式別変更→方式optionの再描画待ち
            if (!string.IsNullOrEmpty(methodText)) _sess.TrySelectByText(_opt.Selectors.SelMethod, methodText);
            Thread.Sleep(500); // 方式変更→馬選択テーブル(ng-switch CC_ID)の再描画待ち

            if (_sess.PageContains(_opt.ClosedText)) return BetResult.Closed;

            int axis = int.TryParse((b.AxisUma ?? "").Trim(), out var a) ? a : -1;
            var partners = Nums(b.Partners);
            int sets = 0;
            void Money() => _sess.SetText(_opt.Selectors.AmountInput, (unit / 100).ToString()); // 100円単位(AngularJSへ確実反映)
            void SetBtn()
            {
                int sel = _sess.ReadSelectedCount(); // セット前に「選択中の投票内容 N組」を確認
                if (sel == 0) Log.Line($"  ⚠ 馬が未選択(0組)。入力列セレクタ/方式の馬テーブル描画を確認してください({b.Venue}{b.Race}R)。");
                else if (sel > 0) Log.Line($"  選択 {sel}組をセットします。");
                _sess.TryClick(_opt.Selectors.SetButton); Thread.Sleep(300); sets++;
            }

            if (bt is "単勝" or "複勝")
            {
                if (axis <= 0) { Log.Line($"  軸馬番が不正({b.Venue}{b.Race}R)。中断。"); return BetResult.Failed; }
                _sess.SetCheckbox(Chk(axis), true); Money(); SetBtn();
            }
            else if (bt == "枠連") // 枠連は枠番テーブル。方式でDOMが異なる: 通常/box=選択列frameNo{枠}(checkbox)、ながし=軸first-no{枠}(radio)+相手second-no{枠}(checkbox)
            {
                string WS(int n) => "input#frameNo" + n;    // 選択列(通常・checkbox)★確認済(bracketqu-basic)
                string WB(int n) => "input#no" + n;         // 選択列(ボックス・checkbox)★確認済(bracketqu-box・枠番でno{枠})
                string WA(int n) => "input#first-no" + n;   // 軸列(ながし・radio)★確認済(bracketqu-wheel)
                string WP(int n) => "input#second-no" + n;  // 相手列(ながし・checkbox)★確認済
                string WF1(int n) => "input#frame1No" + n;  // 枠1列(フォーメーション・checkbox)★確認済(bracketqu-formation)
                string WF2(int n) => "input#frame2No" + n;  // 枠2列(フォーメーション・checkbox)★確認済
                var frames = new List<int>(); if (axis > 0) frames.Add(axis); frames.AddRange(partners); frames = frames.Distinct().ToList();
                if (isNagashi)        // ★確認済DOM: 軸first-no/相手second-no
                {
                    if (axis <= 0 || partners.Count < 1) { Log.Line($"  枠連ながし 軸/相手枠が不足({b.Venue}{b.Race}R)。中断。"); return BetResult.Failed; }
                    _sess.SetCheckbox(WA(axis), true);
                    foreach (var p in partners) _sess.SetCheckbox(WP(p), true);
                }
                else if (isForm)      // ★確認済DOM: フォーメーション=枠1列frame1No/枠2列frame2No(無順2列)
                {
                    var f1 = Nums(b.F1); var f2 = Nums(b.F2);
                    if (f1.Count == 0 || f2.Count == 0) { Log.Line($"  枠連フォーメーション f1/f2枠が不足({b.Venue}{b.Race}R)。中断。"); return BetResult.Failed; }
                    foreach (var u in f1) _sess.SetCheckbox(WF1(u), true);
                    foreach (var u in f2) _sess.SetCheckbox(WF2(u), true);
                }
                else                  // 通常=frameNo{枠}(bracketqu-basic)/ボックス=no{枠}(bracketqu-box)。★両方確認済で別コンポーネント・別ID
                {
                    if (frames.Count < 2) { Log.Line($"  枠連{(isBox ? "ボックス" : "通常")} 枠不足({b.Venue}{b.Race}R)。中断。"); return BetResult.Failed; }
                    foreach (var u in frames) _sess.SetCheckbox(isBox ? WB(u) : WS(u), true);
                }
                Money(); SetBtn();
            }
            else if (isForm) // フォーメーション: f1/f2(/f3)列を各列チェック→1セット
            {
                var f1 = Nums(b.F1); var f2 = Nums(b.F2); var f3 = Nums(b.F3);
                bool need3 = legs == 3;
                if (f1.Count == 0 || f2.Count == 0 || (need3 && f3.Count == 0))
                { Log.Line($"  フォーメーション列(f1/f2{(need3 ? "/f3" : "")})が不足({b.Venue}{b.Race}R)。中断。"); return BetResult.Failed; }
                foreach (var u in f1) _sess.SetCheckbox(H(1, u), true);
                foreach (var u in f2) _sess.SetCheckbox(H(2, u), true);
                if (need3) foreach (var u in f3) _sess.SetCheckbox(H(3, u), true);
                Money(); SetBtn();
            }
            else if (isBox) // ボックス: {軸}∪相手 を単一チェック列で全選択→1セット
            {
                var boxHorses = new List<int>(); if (axis > 0) boxHorses.Add(axis); boxHorses.AddRange(partners);
                boxHorses = boxHorses.Distinct().ToList();
                if (boxHorses.Count < legs) { Log.Line($"  ボックス馬数不足({b.Venue}{b.Race}R)。中断。"); return BetResult.Failed; }
                foreach (var u in boxHorses) _sess.SetCheckbox(Chk(u), true); Money(); SetBtn();
            }
            else if (isNagashi) // ながし: 式別ごとにDOM/軸数が異なる。SetCheckboxはradio/checkbox両対応。
            {
                // 軸馬番リスト(複数軸対応)。Axes列が空ならAxisUma単一を使う。
                var axes = Nums(b.Axes != null && b.Axes.Count > 0 ? b.Axes : new List<string> { b.AxisUma ?? "" });
                if (bt == "三連複")
                {
                    // 軸=horse1_no(軸1頭=radio/軸2頭=checkbox×2)、相手=horse2_no(checkbox)。組=軸1頭C(P,2)/軸2頭P。
                    int need = MethodParse.TrioAxisCount(mh);
                    if (axes.Count < need || partners.Count < 3 - need)
                    { Log.Line($"  三連複ながし 軸{need}頭/相手が不足({b.Venue}{b.Race}R)。中断。"); return BetResult.Failed; }
                    foreach (var ax in axes.Take(need)) _sess.SetCheckbox(H(1, ax), true);
                    foreach (var p in partners) _sess.SetCheckbox(H(2, p), true);
                }
                else if (positional) // 馬単/三連単: 着固定ながし。★単軸と2軸でDOM(列数・ID規則)が異なる
                {
                    var fixedPos = MethodParse.TrifectaFixedPos(mh).Where(p => p <= legs).ToList();
                    if (fixedPos.Count == 0) fixedPos.Add(1);
                    int axisCount = fixedPos.Count;   // 単軸ながし=1 / 2軸ながし(N・M着)=2
                    if (axes.Count < axisCount || partners.Count < legs - axisCount)
                    { Log.Line($"  {bt}着ながし 軸{axisCount}/相手が不足({b.Venue}{b.Race}R)。中断。"); return BetResult.Failed; }
                    if (axisCount == 1)
                    {
                        // 単軸ながし(N着ながし)=2列コンポーネント(trifecta-Nwheel)。軸="N着軸"=col1(horse1_no・radio)、相手=col2(horse2_no・checkbox)。
                        // ★IDは着番号でなく列順(2着ながしでも軸はhorse1_no)。馬単もこちら。
                        _sess.SetCheckbox(H(1, axes[0]), true); Thread.Sleep(150);
                        foreach (var p in partners) _sess.SetCheckbox(H(2, p), true);
                    }
                    else
                    {
                        // 2軸ながし(N・M着ながし)=着順3列コンポーネント。各列=着順位置(col1=1着/col2=2着/col3=3着)固定。
                        // 固定着はその着の列にradio(軸)、流す(欠落)着の列にcheckbox(相手)。例)1・3着→1着col1+3着col3が軸・2着col2が相手。
                        int missing = new[] { 1, 2, 3 }.First(x => !fixedPos.Contains(x));   // 流す着=欠落位置
                        for (int k = 0; k < axisCount; k++) { _sess.SetCheckbox(H(fixedPos[k], axes[k]), true); Thread.Sleep(150); } // 軸=その着の列(排他radio=整定待ち)
                        foreach (var p in partners) _sess.SetCheckbox(H(missing, p), true); // 相手=流す着の列(checkbox)
                    }
                    if (isMulti) _sess.SetCheckbox(_opt.Selectors.MultiCheckbox, true);
                }
                else // 馬連/ワイド/枠連: 軸=horse1_no(radio)、相手=horse2_no(checkbox)
                {
                    int ax1 = axes.Count > 0 ? axes[0] : axis;
                    if (ax1 <= 0 || partners.Count < legs - 1) { Log.Line($"  軸/相手が不足({b.Venue}{b.Race}R)。中断。"); return BetResult.Failed; }
                    _sess.SetCheckbox(H(1, ax1), true);
                    foreach (var p in partners) _sess.SetCheckbox(H(2, p), true);
                }
                Money(); SetBtn();
            }
            else // 通常: 確定した1組
            {
                if (positional) // 馬単/三連単 通常: 着順固定(軸+相手で legs 頭)
                {
                    var order = new List<int>(); if (axis > 0) order.Add(axis); order.AddRange(partners);
                    if (order.Count < legs) { Log.Line($"  通常の馬番不足({b.Venue}{b.Race}R)。中断。"); return BetResult.Failed; }
                    // 各列は排他ラジオ(1着/2着/3着)。選択ごとに全行のng-disabledが再評価されるため、
                    // 整定待ちを挟まないと次列(特に3着)のクリックがdigest中に取りこぼされる。
                    for (int k = 0; k < legs; k++) { _sess.SetCheckbox(H(k + 1, order[k]), true); Thread.Sleep(150); }
                }
                else // 枠連/馬連/ワイド/三連複 通常: 単一チェック列で legs 頭
                {
                    var sel = new List<int>(); if (axis > 0) sel.Add(axis); sel.AddRange(partners);
                    sel = sel.Distinct().ToList();
                    if (sel.Count < legs) { Log.Line($"  通常の馬番不足({b.Venue}{b.Race}R)。中断。"); return BetResult.Failed; }
                    foreach (var u in sel.Take(legs)) _sess.SetCheckbox(Chk(u), true);
                }
                Money(); SetBtn();
            }
            Log.Line($"  {b.Venue}{b.Race}R {bt}{(string.IsNullOrEmpty(mh) ? "" : " " + mh)}: {sets}件セット(各{unit:N0}円・計{spent:N0}円)。");

            // 2) 入力終了→購入予定リスト(カート)
            _sess.TryClick(_opt.Selectors.PurchaseButton);
            _sess.WaitForExists(_opt.Selectors.ConfirmAmountInput, TimeSpan.FromSeconds(10));
            if (_sess.PageContains(_opt.ClosedText)) return BetResult.Closed;

            if (_opt.ResolvedMode == BetMode.ConfirmStop)
            {
                // 合計金額(getCalcTotalAmount)はカート展開直後は未計算→描画されるまでポーリングしてから合計金額入力へ充填。
                int shown = 0;
                for (int i = 0; i < 16 && shown <= 0; i++) { shown = _sess.ReadCartTotal(); if (shown <= 0) Thread.Sleep(250); }
                if (shown > 0) _sess.SetText(_opt.Selectors.ConfirmAmountInput, shown.ToString());
                Log.Line($"  ★確認停止: 購入予定リスト表示・合計金額{(shown > 0 ? shown.ToString("N0") + "円を充填" : "(表示額0=各馬券の金額/選択を要確認)")}。『購入する』と確認OKはご自身で(自動では確定しません)。");
                return BetResult.StoppedForConfirm;
            }

            // Auto(較正後の実課金): 画面の合計金額(getCalcTotalAmount)と同額を合計金額入力→購入する→確認ポップアップOK→完了待ち
            int shownTotal = 0;
            for (int i = 0; i < 16 && shownTotal <= 0; i++) { shownTotal = _sess.ReadCartTotal(); if (shownTotal <= 0) Thread.Sleep(250); }
            int confirmAmt = shownTotal > 0 ? shownTotal : spent; // 表示額優先(取消等で計算と差異あり得る)
            _sess.SetText(_opt.Selectors.ConfirmAmountInput, confirmAmt.ToString());
            _sess.TryClick(_opt.Selectors.VoteSubmit); // 「購入する」
            // 「投票内容と金額を送信してもよろしいですか？」ポップアップのOK=実際の課金発火点
            _sess.WaitForExists(_opt.Selectors.VoteConfirmOk, TimeSpan.FromSeconds(8));
            _sess.TryClick(_opt.Selectors.VoteConfirmOk);
            return _sess.WaitForVoteCompleted(_opt.CompletedText, 25) ? BetResult.Purchased : BetResult.Failed; // 完了=「投票を受け付けました/受付番号」
        }
        catch (Exception ex) { Log.Line($"  投票でエラー {b.Venue}{b.Race}R: {ex.Message}"); return BetResult.Failed; }
    }
}

/// <summary>入金(即PAT入金)。確認画面の「入金する」直前で必ず停止(Autoは作らない)。</summary>
public sealed class DepositPage
{
    readonly IpatOptions _opt; readonly IpatSession _sess;
    public DepositPage(IpatOptions opt, IpatSession sess) { _opt = opt; _sess = sess; }
    static bool IsTodo(string s) => string.IsNullOrWhiteSpace(s) || s.StartsWith("TODO_");

    public static int ComputePlannedTotal(List<BetTicket> bets, IpatOptions opt)
        => bets.Sum(b => Points.ForTicket(b, opt) * (b.StakeYen > 0 ? Math.Max(100, b.StakeYen / 100 * 100) : opt.StakePerPointYen));

    public DepositResult Run(List<BetTicket> bets, int amountOverride, out int amount)
    {
        amount = amountOverride > 0 ? amountOverride : ComputePlannedTotal(bets, _opt) + _opt.Deposit.BufferYen;
        amount = Math.Max(0, amount / 100 * 100);
        if (amount <= 0) { Log.Line("入金額0=不要。"); return DepositResult.Skipped; }
        if (amount > _opt.Deposit.MaxDepositYen) { Log.Line($"[安全弁] 計算入金額 {amount:N0}円 > 上限 {_opt.Deposit.MaxDepositYen:N0}円。中止。"); return DepositResult.Failed; }
        if (_opt.ResolvedMode == BetMode.DryRun) { Log.Line($"[DryRun] 入金プレビュー {amount:N0}円(実行なし)。"); return DepositResult.Planned; }
        if (IsTodo(_opt.Deposit.MenuDeposit) || IsTodo(_opt.Deposit.AmountInput) || IsTodo(_opt.Deposit.NextButton) || IsTodo(_opt.Deposit.PinInput))
        {
            Log.Line("【未較正】入金セレクタがプレースホルダ。入金は行いません(ipat.json Deposit較正要)。");
            return DepositResult.Failed;
        }
        try
        {
            // ★入金は実資金。DryRun以外でも『実行』とJS確認ポップアップは人が押す(直前で停止=Autoでも自動確定しない)。
            // 投票メニューの入金ボタン→別窓(SP入出金サイト)→①金額NYUKIN→次へ→②確認画面の暗証PASS_WORD→ここで停止。
            // 入金フォームは購入限度額(ネットバンク情報)の非同期ロード後に描画される→ボタン出現を待ってからクリック
            if (!_sess.WaitForExists(_opt.Deposit.MenuDeposit, TimeSpan.FromSeconds(6)))
            { Log.Line("入金ボタン(入金(チャージ))が見つかりません=中止。"); return DepositResult.Failed; }
            int prior = _sess.WindowCount;
            _sess.TryClick(_opt.Deposit.MenuDeposit);
            if (!_sess.SwitchToNewWindow(prior, TimeSpan.FromSeconds(6)))
            { Log.Line("入金ウィンドウ(別窓)が開きません。中止。"); return DepositResult.Failed; }
            if (!_sess.WaitForExists(_opt.Deposit.AmountInput, TimeSpan.FromSeconds(12)))
            { Log.Line("入金額入力画面を確認できません。中止。"); return DepositResult.Failed; }
            _sess.TrySendKeys(_opt.Deposit.AmountInput, amount.ToString());
            _sess.TryClick(_opt.Deposit.NextButton);
            if (!_sess.WaitForExists(_opt.Deposit.PinInput, TimeSpan.FromSeconds(12)))
            { Log.Line("入金確認画面(暗証番号)を確認できません。中止。"); return DepositResult.Failed; }
            var pin = Secrets.Pin;
            if (!string.IsNullOrWhiteSpace(pin)) _sess.TrySendKeys(_opt.Deposit.PinInput, pin!);

            if (_opt.ResolvedMode == BetMode.Auto)
            {   // Auto=全自動課金: 【実行】→ネイティブ確認「入金します。よろしいですか？」をOK自動承認(実資金)。MaxDepositYen安全弁は通過済。
                Log.Line($"★入金 {amount:N0}円 [Auto実課金]: 【実行】クリック→確認ダイアログOKを自動承認します。");
                _sess.TryClick(_opt.Deposit.SubmitButton);                                  // 実行(緑ボタン)
                bool ok = _sess.AcceptAlert(TimeSpan.FromSeconds(8));                       // 「入金します。よろしいですか？」OK
                Log.Line(ok ? "確認ダイアログをOK(承認)しました。" : "確認ダイアログ未検出(実行ボタン/タイミング要確認・未入金の可能性)。");
                if (_sess.WaitForVoteCompleted(_opt.Deposit.CompletedText, 20))
                { Log.Line($"入金指示完了を確認({amount:N0}円)。"); return DepositResult.Done; }
                Log.Line("入金完了表示を確認できませんでした(未確定/セレクタ要確認)。");
                return DepositResult.Failed;
            }

            // ConfirmStop: 【実行】とJS確認OKは人が押す(直前で停止)
            Log.Line($"★入金 {amount:N0}円: 金額と暗証番号を入力しました。確認画面の【実行】ボタンと『入金します。よろしいですか？』のOKは必ずご自身で押してください(自動では押しません)。");
            return DepositResult.StoppedForConfirm;
        }
        catch (Exception ex) { Log.Line($"入金でエラー: {ex.Message}"); return DepositResult.Failed; }
    }
}

/// <summary>照会(残高・購入・払戻・収支)。読み取り専用。★較正後に実装。</summary>
public sealed class ReferencePage
{
    readonly IpatOptions _opt; readonly IpatSession _sess;
    public ReferencePage(IpatOptions opt, IpatSession sess) { _opt = opt; _sess = sess; }
    public List<(string label, string value)> ReadDetailedBalance()
    {
        // TODO(較正後): 照会メニュー→当日購入/払戻/残高 を読み取り。現状は空。
        return new List<(string, string)>();
    }
}
