// 役割: DBに保存されたリアルタイムオッズを画面で確認するフォームです。
// レースを選択し、ChartServiceで作成したOxyPlotの系列を表示します。
using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows.Forms;
using 中央競馬.共通.Data;
using 中央競馬.共通.Models;

namespace RealTimeOddsChart
{
    public partial class RealTimeOddsChart : Form
    {
        private List<string> _xLabels = new();
        private List<リアルタイムオッズモデル> _oddsList = new();

        public RealTimeOddsChart()
        {
            InitializeComponent();
            Load初期データ();
        }

        private void Load初期データ()
        {
            using var db = new DBContext();

            var dates = db.リアルタイムオッズ
                .Select(o => o.開催日)
                .Distinct()
                .OrderByDescending(d => d)
                .ToList();

            if (dates.Any()) 開催日.Value = dates.First().ToDateTime(TimeOnly.MinValue);

            comboBox開催場所.Items.Clear();
            comboBox開催場所.Items.AddRange(
                db.リアルタイムオッズ
                    .Select(o => o.開催場所)
                    .Distinct()
                    .OrderBy(x => x)
                    .ToArray());

            if (comboBox開催場所.Items.Count > 0)
                comboBox開催場所.SelectedIndex = 0;

            comboBoxレース番号.Items.Clear();
            for (int i = 1; i <= 12; i++) comboBoxレース番号.Items.Add(i.ToString());
            comboBoxレース番号.SelectedIndex = 0;
        }

        private void button表示_Click(object? sender, EventArgs e)
        {
            var 開催日Val = DateOnly.FromDateTime(開催日.Value);
            var 開催場所Val = comboBox開催場所.Text;
            var レース番号Val = int.Parse(comboBoxレース番号.Text);

            using var db = new DBContext();
            _oddsList = db.リアルタイムオッズ
                .Where(o => o.開催日 == 開催日Val &&
                            o.開催場所 == 開催場所Val &&
                            o.レース番号 == レース番号Val)
                .ToList();

            if (!_oddsList.Any())
            {
                MessageBox.Show("該当データがありません。");
                return;
            }

            cartesianChart1.Series = ChartService.CreateOddsSeries(_oddsList, out _xLabels);
            cartesianChart1.XAxes = ChartService.CreateXAxis(_xLabels);
            cartesianChart1.YAxes = ChartService.CreateYAxis();
        }
    }
}
