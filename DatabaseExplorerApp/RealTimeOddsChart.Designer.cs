// 役割: RealTimeOddsChartフォームのコントロール定義とレイアウトを保持するDesignerコードです。
// グラフ描画ロジックはRealTimeOddsChart.csとChartService.cs側で管理します。
using LiveChartsCore;
using LiveChartsCore.SkiaSharpView;
using LiveChartsCore.SkiaSharpView.WinForms;

namespace RealTimeOddsChart
{
    partial class RealTimeOddsChart
    {
        private System.ComponentModel.IContainer components = null;
        private System.Windows.Forms.Label lblDate;
        private System.Windows.Forms.DateTimePicker 開催日;
        private System.Windows.Forms.ComboBox comboBox開催場所;
        private System.Windows.Forms.ComboBox comboBoxレース番号;
        private System.Windows.Forms.Button button表示;
        private LiveChartsCore.SkiaSharpView.WinForms.CartesianChart cartesianChart1;

        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null)) components.Dispose();
            base.Dispose(disposing);
        }

        private void InitializeComponent()
        {
            lblDate = new Label();
            開催日 = new DateTimePicker();
            comboBox開催場所 = new ComboBox();
            comboBoxレース番号 = new ComboBox();
            button表示 = new Button();
            cartesianChart1 = new LiveChartsCore.SkiaSharpView.WinForms.CartesianChart();
            SuspendLayout();
            // 
            // lblDate
            // 
            lblDate.AutoSize = true;
            lblDate.Location = new Point(12, 15);
            lblDate.Name = "lblDate";
            lblDate.Size = new Size(84, 25);
            lblDate.TabIndex = 0;
            lblDate.Text = "開催日：";
            // 
            // 開催日
            // 
            開催日.Format = DateTimePickerFormat.Short;
            開催日.Location = new Point(92, 6);
            開催日.Name = "開催日";
            開催日.Size = new Size(200, 31);
            開催日.TabIndex = 1;
            // 
            // comboBox開催場所
            // 
            comboBox開催場所.DropDownStyle = ComboBoxStyle.DropDownList;
            comboBox開催場所.Location = new Point(298, 4);
            comboBox開催場所.Name = "comboBox開催場所";
            comboBox開催場所.Size = new Size(121, 33);
            comboBox開催場所.TabIndex = 2;
            // 
            // comboBoxレース番号
            // 
            comboBoxレース番号.DropDownStyle = ComboBoxStyle.DropDownList;
            comboBoxレース番号.Location = new Point(425, 4);
            comboBoxレース番号.Name = "comboBoxレース番号";
            comboBoxレース番号.Size = new Size(121, 33);
            comboBoxレース番号.TabIndex = 3;
            // 
            // button表示
            // 
            button表示.Location = new Point(621, 6);
            button表示.Name = "button表示";
            button表示.Size = new Size(77, 34);
            button表示.TabIndex = 4;
            button表示.Text = "表示";
            button表示.Click += button表示_Click;
            // 
            // cartesianChart1
            // 
            cartesianChart1.Dock = DockStyle.Bottom;
            cartesianChart1.Location = new Point(0, 46);
            cartesianChart1.Name = "cartesianChart1";
            cartesianChart1.Size = new Size(1523, 812);
            cartesianChart1.TabIndex = 5;
            // 
            // RealTimeOddsChart
            // 
            ClientSize = new Size(1523, 858);
            Controls.Add(lblDate);
            Controls.Add(開催日);
            Controls.Add(comboBox開催場所);
            Controls.Add(comboBoxレース番号);
            Controls.Add(button表示);
            Controls.Add(cartesianChart1);
            Name = "RealTimeOddsChart";
            Text = "リアルタイム単勝オッズグラフ";
            ResumeLayout(false);
            PerformLayout();
        }
    }
}
