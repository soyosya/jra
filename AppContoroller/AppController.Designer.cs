// 役割: AppControllerフォームのコントロール定義とレイアウトを保持するDesignerコードです。
// ボタン名やツールチップは画面表示に関わるため確認対象ですが、通常の処理ロジックはAppController.cs側に置きます。
namespace AppController
{
    partial class AppController
    {
        /// <summary>
        ///  Required designer variable.
        /// </summary>
        private System.ComponentModel.IContainer components = null;

        /// <summary>
        ///  Clean up any resources being used.
        /// </summary>
        /// <param name="disposing">true if managed resources should be disposed; otherwise, false.</param>
        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null))
            {
                components.Dispose();
            }
            base.Dispose(disposing);
        }

        #region Windows Form Designer generated code

        /// <summary>
        ///  Required method for Designer support - do not modify
        ///  the contents of this method with the code editor.
        /// </summary>
        private void InitializeComponent()
        {
            components = new System.ComponentModel.Container();
            realtimeodds_start_button = new Button();
            toolTip1 = new ToolTip(components);
            realtimeodds_stop_button = new Button();
            raceInfo_start_button = new Button();
            raceInfo_stop_button = new Button();
            realtimeraceinfo_start_button = new Button();
            realtimeraceinfo_stop_button = new Button();
            reaceresult_start_button = new Button();
            raceresult_stop_button = new Button();
            reaceresultByhorce_start_button = new Button();
            reaceresultByhorce_stop_button = new Button();
            raceInfo_from_dateTimePicker = new DateTimePicker();
            raceInfo_to_dateTimePicker = new DateTimePicker();
            RaceAnalyzer_RaceDate = new DateTimePicker();
            RaceAnalyzer_start_button = new Button();
            RaceAnalyzer_stop_button = new Button();
            statusStrip1 = new StatusStrip();
            toolStripStatusLabel_CurrentDateTime = new ToolStripStatusLabel();
            toolStripStatusLabel_notify = new ToolStripStatusLabel();
            timer_CurrentDateTime = new System.Windows.Forms.Timer(components);
            realtimeodds_groupBox = new GroupBox();
            raceInfo_groupBox = new GroupBox();
            realtimeraceinfo_groupBox = new GroupBox();
            raceresult_groupBox = new GroupBox();
            個別穴埋め_groupBox = new GroupBox();
            RaceAnalyzer_groupBox = new GroupBox();
            RaceAnalyzer_RaceNo_comboBox = new ComboBox();
            RaceAnalyzer_Racecourse_comboBox = new ComboBox();
            button1 = new Button();
            statusStrip1.SuspendLayout();
            realtimeodds_groupBox.SuspendLayout();
            raceInfo_groupBox.SuspendLayout();
            realtimeraceinfo_groupBox.SuspendLayout();
            raceresult_groupBox.SuspendLayout();
            個別穴埋め_groupBox.SuspendLayout();
            RaceAnalyzer_groupBox.SuspendLayout();
            SuspendLayout();
            // 
            // realtimeodds_start_button
            // 
            realtimeodds_start_button.Location = new Point(40, 42);
            realtimeodds_start_button.Name = "realtimeodds_start_button";
            realtimeodds_start_button.Size = new Size(169, 34);
            realtimeodds_start_button.TabIndex = 0;
            realtimeodds_start_button.Text = "開始";
            toolTip1.SetToolTip(realtimeodds_start_button, "リアルタイムオッズ取得開始");
            realtimeodds_start_button.UseVisualStyleBackColor = true;
            realtimeodds_start_button.Click += realtimeodds_strat_button_Click;
            // 
            // realtimeodds_stop_button
            // 
            realtimeodds_stop_button.Location = new Point(40, 82);
            realtimeodds_stop_button.Name = "realtimeodds_stop_button";
            realtimeodds_stop_button.Size = new Size(169, 34);
            realtimeodds_stop_button.TabIndex = 2;
            realtimeodds_stop_button.Text = "終了";
            toolTip1.SetToolTip(realtimeodds_stop_button, "リアルタイムオッズ取得終了");
            realtimeodds_stop_button.UseVisualStyleBackColor = true;
            realtimeodds_stop_button.Click += realtimeodds_stop_button_Click;
            // 
            // raceInfo_start_button
            // 
            raceInfo_start_button.Location = new Point(40, 42);
            raceInfo_start_button.Name = "raceInfo_start_button";
            raceInfo_start_button.Size = new Size(169, 34);
            raceInfo_start_button.TabIndex = 0;
            raceInfo_start_button.Text = "開始";
            toolTip1.SetToolTip(raceInfo_start_button, "レース情報取得開始");
            raceInfo_start_button.UseVisualStyleBackColor = true;
            raceInfo_start_button.Click += raceInfo_start_button_Click;
            // 
            // raceInfo_stop_button
            // 
            raceInfo_stop_button.Location = new Point(40, 82);
            raceInfo_stop_button.Name = "raceInfo_stop_button";
            raceInfo_stop_button.Size = new Size(169, 34);
            raceInfo_stop_button.TabIndex = 2;
            raceInfo_stop_button.Text = "終了";
            toolTip1.SetToolTip(raceInfo_stop_button, "レース情報取得終了");
            raceInfo_stop_button.UseVisualStyleBackColor = true;
            raceInfo_stop_button.Click += raceInfo_stop_button_Click;
            // 
            // realtimeraceinfo_start_button
            // 
            realtimeraceinfo_start_button.Location = new Point(40, 42);
            realtimeraceinfo_start_button.Name = "realtimeraceinfo_start_button";
            realtimeraceinfo_start_button.Size = new Size(169, 34);
            realtimeraceinfo_start_button.TabIndex = 0;
            realtimeraceinfo_start_button.Text = "開始";
            toolTip1.SetToolTip(realtimeraceinfo_start_button, "リアルタイムレース情報取得開始");
            realtimeraceinfo_start_button.UseVisualStyleBackColor = true;
            realtimeraceinfo_start_button.Click += realtimeraceinfo_start_button_Click;
            // 
            // realtimeraceinfo_stop_button
            // 
            realtimeraceinfo_stop_button.Location = new Point(40, 82);
            realtimeraceinfo_stop_button.Name = "realtimeraceinfo_stop_button";
            realtimeraceinfo_stop_button.Size = new Size(169, 34);
            realtimeraceinfo_stop_button.TabIndex = 2;
            realtimeraceinfo_stop_button.Text = "終了";
            toolTip1.SetToolTip(realtimeraceinfo_stop_button, "リアルタイムレース情報取得終了");
            realtimeraceinfo_stop_button.UseVisualStyleBackColor = true;
            realtimeraceinfo_stop_button.Click += realtimeraceinfo_stop_button_Click;
            // 
            // reaceresult_start_button
            // 
            reaceresult_start_button.Location = new Point(40, 42);
            reaceresult_start_button.Name = "reaceresult_start_button";
            reaceresult_start_button.Size = new Size(169, 34);
            reaceresult_start_button.TabIndex = 0;
            reaceresult_start_button.Text = "開始";
            toolTip1.SetToolTip(reaceresult_start_button, "競走結果・払戻金の欠落補完開始");
            reaceresult_start_button.UseVisualStyleBackColor = true;
            reaceresult_start_button.Click += reaceresult_start_button_Click;
            // 
            // raceresult_stop_button
            // 
            raceresult_stop_button.Location = new Point(40, 82);
            raceresult_stop_button.Name = "raceresult_stop_button";
            raceresult_stop_button.Size = new Size(169, 34);
            raceresult_stop_button.TabIndex = 2;
            raceresult_stop_button.Text = "終了";
            toolTip1.SetToolTip(raceresult_stop_button, "競走結果・払戻金の欠落補完終了");
            raceresult_stop_button.UseVisualStyleBackColor = true;
            raceresult_stop_button.Click += raceresult_stop_button_Click;
            // 
            // reaceresultByhorce_start_button
            // 
            reaceresultByhorce_start_button.Location = new Point(40, 42);
            reaceresultByhorce_start_button.Name = "reaceresultByhorce_start_button";
            reaceresultByhorce_start_button.Size = new Size(169, 34);
            reaceresultByhorce_start_button.TabIndex = 0;
            reaceresultByhorce_start_button.Text = "開始";
            toolTip1.SetToolTip(reaceresultByhorce_start_button, "馬別の競走履歴補完開始");
            reaceresultByhorce_start_button.UseVisualStyleBackColor = true;
            reaceresultByhorce_start_button.Click += reaceresultByhorce_start_button_Click;
            // 
            // reaceresultByhorce_stop_button
            // 
            reaceresultByhorce_stop_button.Location = new Point(40, 82);
            reaceresultByhorce_stop_button.Name = "reaceresultByhorce_stop_button";
            reaceresultByhorce_stop_button.Size = new Size(169, 34);
            reaceresultByhorce_stop_button.TabIndex = 2;
            reaceresultByhorce_stop_button.Text = "終了";
            toolTip1.SetToolTip(reaceresultByhorce_stop_button, "馬別の競走履歴補完終了");
            reaceresultByhorce_stop_button.UseVisualStyleBackColor = true;
            // 
            // raceInfo_from_dateTimePicker
            // 
            raceInfo_from_dateTimePicker.Format = DateTimePickerFormat.Short;
            raceInfo_from_dateTimePicker.Location = new Point(41, 132);
            raceInfo_from_dateTimePicker.Name = "raceInfo_from_dateTimePicker";
            raceInfo_from_dateTimePicker.Size = new Size(169, 31);
            raceInfo_from_dateTimePicker.TabIndex = 3;
            toolTip1.SetToolTip(raceInfo_from_dateTimePicker, "レース情報を取得する範囲（開始日）を指定する");
            // 
            // raceInfo_to_dateTimePicker
            // 
            raceInfo_to_dateTimePicker.Format = DateTimePickerFormat.Short;
            raceInfo_to_dateTimePicker.Location = new Point(41, 169);
            raceInfo_to_dateTimePicker.Name = "raceInfo_to_dateTimePicker";
            raceInfo_to_dateTimePicker.Size = new Size(169, 31);
            raceInfo_to_dateTimePicker.TabIndex = 4;
            toolTip1.SetToolTip(raceInfo_to_dateTimePicker, "レース情報を取得する範囲（終了日）を指定する");
            // 
            // RaceAnalyzer_RaceDate
            // 
            RaceAnalyzer_RaceDate.Format = DateTimePickerFormat.Short;
            RaceAnalyzer_RaceDate.Location = new Point(40, 110);
            RaceAnalyzer_RaceDate.Name = "RaceAnalyzer_RaceDate";
            RaceAnalyzer_RaceDate.Size = new Size(169, 31);
            RaceAnalyzer_RaceDate.TabIndex = 3;
            toolTip1.SetToolTip(RaceAnalyzer_RaceDate, "対戦評価の対象日を指定する");
            RaceAnalyzer_RaceDate.ValueChanged += RaceAnalyzer_RaceDate_ValueChanged;
            // 
            // RaceAnalyzer_start_button
            // 
            RaceAnalyzer_start_button.Location = new Point(40, 30);
            RaceAnalyzer_start_button.Name = "RaceAnalyzer_start_button";
            RaceAnalyzer_start_button.Size = new Size(169, 34);
            RaceAnalyzer_start_button.TabIndex = 0;
            RaceAnalyzer_start_button.Text = "開始";
            toolTip1.SetToolTip(RaceAnalyzer_start_button, "対戦評価開始");
            RaceAnalyzer_start_button.UseVisualStyleBackColor = true;
            RaceAnalyzer_start_button.Click += RaceAnalyzer_start_button_Click;
            // 
            // RaceAnalyzer_stop_button
            // 
            RaceAnalyzer_stop_button.Location = new Point(40, 70);
            RaceAnalyzer_stop_button.Name = "RaceAnalyzer_stop_button";
            RaceAnalyzer_stop_button.Size = new Size(169, 34);
            RaceAnalyzer_stop_button.TabIndex = 2;
            RaceAnalyzer_stop_button.Text = "終了";
            toolTip1.SetToolTip(RaceAnalyzer_stop_button, "対戦評価終了");
            RaceAnalyzer_stop_button.UseVisualStyleBackColor = true;
            // 
            // statusStrip1
            // 
            statusStrip1.ImageScalingSize = new Size(24, 24);
            statusStrip1.Items.AddRange(new ToolStripItem[] { toolStripStatusLabel_CurrentDateTime, toolStripStatusLabel_notify });
            statusStrip1.Location = new Point(0, 511);
            statusStrip1.Name = "statusStrip1";
            statusStrip1.Size = new Size(800, 32);
            statusStrip1.TabIndex = 1;
            statusStrip1.Text = "statusStrip1";
            // 
            // toolStripStatusLabel_CurrentDateTime
            // 
            toolStripStatusLabel_CurrentDateTime.Name = "toolStripStatusLabel_CurrentDateTime";
            toolStripStatusLabel_CurrentDateTime.Size = new Size(665, 25);
            toolStripStatusLabel_CurrentDateTime.Spring = true;
            toolStripStatusLabel_CurrentDateTime.Text = "日時";
            // 
            // toolStripStatusLabel_notify
            // 
            toolStripStatusLabel_notify.Name = "toolStripStatusLabel_notify";
            toolStripStatusLabel_notify.Size = new Size(120, 25);
            toolStripStatusLabel_notify.Text = "メッセージエリア";
            // 
            // timer_CurrentDateTime
            // 
            timer_CurrentDateTime.Enabled = true;
            // 
            // realtimeodds_groupBox
            // 
            realtimeodds_groupBox.Controls.Add(realtimeodds_start_button);
            realtimeodds_groupBox.Controls.Add(realtimeodds_stop_button);
            realtimeodds_groupBox.Location = new Point(12, 12);
            realtimeodds_groupBox.Name = "realtimeodds_groupBox";
            realtimeodds_groupBox.Size = new Size(238, 141);
            realtimeodds_groupBox.TabIndex = 3;
            realtimeodds_groupBox.TabStop = false;
            realtimeodds_groupBox.Text = "リアルタイムオッズ";
            // 
            // raceInfo_groupBox
            // 
            raceInfo_groupBox.Controls.Add(raceInfo_to_dateTimePicker);
            raceInfo_groupBox.Controls.Add(raceInfo_from_dateTimePicker);
            raceInfo_groupBox.Controls.Add(raceInfo_start_button);
            raceInfo_groupBox.Controls.Add(raceInfo_stop_button);
            raceInfo_groupBox.Location = new Point(12, 173);
            raceInfo_groupBox.Name = "raceInfo_groupBox";
            raceInfo_groupBox.Size = new Size(238, 226);
            raceInfo_groupBox.TabIndex = 4;
            raceInfo_groupBox.TabStop = false;
            raceInfo_groupBox.Text = "レース情報";
            // 
            // realtimeraceinfo_groupBox
            // 
            realtimeraceinfo_groupBox.Controls.Add(realtimeraceinfo_start_button);
            realtimeraceinfo_groupBox.Controls.Add(realtimeraceinfo_stop_button);
            realtimeraceinfo_groupBox.Location = new Point(277, 28);
            realtimeraceinfo_groupBox.Name = "realtimeraceinfo_groupBox";
            realtimeraceinfo_groupBox.Size = new Size(238, 141);
            realtimeraceinfo_groupBox.TabIndex = 5;
            realtimeraceinfo_groupBox.TabStop = false;
            realtimeraceinfo_groupBox.Text = "リアルタイムレース情報";
            // 
            // raceresult_groupBox
            // 
            raceresult_groupBox.Controls.Add(reaceresult_start_button);
            raceresult_groupBox.Controls.Add(raceresult_stop_button);
            raceresult_groupBox.Location = new Point(550, 12);
            raceresult_groupBox.Name = "raceresult_groupBox";
            raceresult_groupBox.Size = new Size(238, 141);
            raceresult_groupBox.TabIndex = 6;
            raceresult_groupBox.TabStop = false;
            raceresult_groupBox.Text = "競走結果・払戻金穴埋め";
            // 
            // 個別穴埋め_groupBox
            // 
            個別穴埋め_groupBox.Controls.Add(reaceresultByhorce_start_button);
            個別穴埋め_groupBox.Controls.Add(reaceresultByhorce_stop_button);
            個別穴埋め_groupBox.Location = new Point(550, 173);
            個別穴埋め_groupBox.Name = "個別穴埋め_groupBox";
            個別穴埋め_groupBox.Size = new Size(238, 141);
            個別穴埋め_groupBox.TabIndex = 7;
            個別穴埋め_groupBox.TabStop = false;
            個別穴埋め_groupBox.Text = "馬別競走履歴穴埋め";
            // 
            // RaceAnalyzer_groupBox
            // 
            RaceAnalyzer_groupBox.Controls.Add(RaceAnalyzer_RaceNo_comboBox);
            RaceAnalyzer_groupBox.Controls.Add(RaceAnalyzer_Racecourse_comboBox);
            RaceAnalyzer_groupBox.Controls.Add(RaceAnalyzer_RaceDate);
            RaceAnalyzer_groupBox.Controls.Add(RaceAnalyzer_start_button);
            RaceAnalyzer_groupBox.Controls.Add(RaceAnalyzer_stop_button);
            RaceAnalyzer_groupBox.Location = new Point(277, 195);
            RaceAnalyzer_groupBox.Name = "RaceAnalyzer_groupBox";
            RaceAnalyzer_groupBox.Size = new Size(238, 247);
            RaceAnalyzer_groupBox.TabIndex = 8;
            RaceAnalyzer_groupBox.TabStop = false;
            RaceAnalyzer_groupBox.Text = "対戦評価";
            // 
            // RaceAnalyzer_RaceNo_comboBox
            // 
            RaceAnalyzer_RaceNo_comboBox.DropDownStyle = ComboBoxStyle.DropDownList;
            RaceAnalyzer_RaceNo_comboBox.FormattingEnabled = true;
            RaceAnalyzer_RaceNo_comboBox.Location = new Point(40, 188);
            RaceAnalyzer_RaceNo_comboBox.Name = "RaceAnalyzer_RaceNo_comboBox";
            RaceAnalyzer_RaceNo_comboBox.Size = new Size(169, 33);
            RaceAnalyzer_RaceNo_comboBox.TabIndex = 8;
            // 
            // RaceAnalyzer_Racecourse_comboBox
            // 
            RaceAnalyzer_Racecourse_comboBox.DropDownStyle = ComboBoxStyle.DropDownList;
            RaceAnalyzer_Racecourse_comboBox.FormattingEnabled = true;
            RaceAnalyzer_Racecourse_comboBox.Location = new Point(40, 149);
            RaceAnalyzer_Racecourse_comboBox.Name = "RaceAnalyzer_Racecourse_comboBox";
            RaceAnalyzer_Racecourse_comboBox.Size = new Size(169, 33);
            RaceAnalyzer_Racecourse_comboBox.TabIndex = 6;
            RaceAnalyzer_Racecourse_comboBox.ValueMemberChanged += RaceAnalyzer_Racecourse_comboBox_ValueMemberChanged;
            RaceAnalyzer_Racecourse_comboBox.SelectedValueChanged += RaceAnalyzer_Racecourse_comboBox_SelectedValueChanged;
            // 
            // button1
            // 
            button1.Location = new Point(590, 344);
            button1.Name = "button1";
            button1.Size = new Size(169, 34);
            button1.TabIndex = 9;
            button1.Text = "対戦評価テスト";
            toolTip1.SetToolTip(button1, "固定条件で対戦評価テストを実行");
            button1.UseVisualStyleBackColor = true;
            button1.Click += button1_Click;
            // 
            // AppController
            // 
            AutoScaleDimensions = new SizeF(10F, 25F);
            AutoScaleMode = AutoScaleMode.Font;
            ClientSize = new Size(800, 543);
            Controls.Add(button1);
            Controls.Add(RaceAnalyzer_groupBox);
            Controls.Add(個別穴埋め_groupBox);
            Controls.Add(raceresult_groupBox);
            Controls.Add(realtimeraceinfo_groupBox);
            Controls.Add(raceInfo_groupBox);
            Controls.Add(realtimeodds_groupBox);
            Controls.Add(statusStrip1);
            Name = "AppController";
            Text = "AppController";
            Load += AppController_Load;
            statusStrip1.ResumeLayout(false);
            statusStrip1.PerformLayout();
            realtimeodds_groupBox.ResumeLayout(false);
            raceInfo_groupBox.ResumeLayout(false);
            realtimeraceinfo_groupBox.ResumeLayout(false);
            raceresult_groupBox.ResumeLayout(false);
            個別穴埋め_groupBox.ResumeLayout(false);
            RaceAnalyzer_groupBox.ResumeLayout(false);
            ResumeLayout(false);
            PerformLayout();
        }

        #endregion

        private Button realtimeodds_start_button;
        private ToolTip toolTip1;
        private StatusStrip statusStrip1;
        private ToolStripStatusLabel toolStripStatusLabel_CurrentDateTime;
        private System.Windows.Forms.Timer timer_CurrentDateTime;
        private ToolStripStatusLabel toolStripStatusLabel_notify;
        private Button realtimeodds_stop_button;
        private GroupBox realtimeodds_groupBox;
        private GroupBox raceInfo_groupBox;
        private Button raceInfo_start_button;
        private Button raceInfo_stop_button;
        private GroupBox realtimeraceinfo_groupBox;
        private Button realtimeraceinfo_start_button;
        private Button realtimeraceinfo_stop_button;
        private GroupBox raceresult_groupBox;
        private Button reaceresult_start_button;
        private Button raceresult_stop_button;
        private GroupBox 個別穴埋め_groupBox;
        private Button reaceresultByhorce_start_button;
        private Button reaceresultByhorce_stop_button;
        private DateTimePicker raceInfo_from_dateTimePicker;
        private DateTimePicker raceInfo_to_dateTimePicker;
        private GroupBox RaceAnalyzer_groupBox;
        private DateTimePicker RaceAnalyzer_RaceDate;
        private Button RaceAnalyzer_start_button;
        private Button RaceAnalyzer_stop_button;
        private ComboBox RaceAnalyzer_Racecourse_comboBox;
        private ComboBox RaceAnalyzer_RaceNo_comboBox;
        private Button button1;
    }
}
