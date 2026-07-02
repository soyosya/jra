' 自動投票ランチャーをコンソール窓なしで起動するラッパー。
' Task Scheduler が pwsh を対話セッションで起動すると黒い窓が出るため、
' このVBSを経由して pwsh を hidden(0) で起動し、窓を出さずにバックグラウンド実行する。
' (ランナーはChrome投票のため対話セッションが必要だが、窓自体は不要)
' 受け取った引数(=pwshへ渡す引数)をそのまま hidden で pwsh.exe に渡す。
Option Explicit
' conhost.exe 経由で起動することで、既定端末がWindows Terminalでも
' クラシックの隠しコンソールに収め、ランナーの子プロセス(fetch-odds等)が
' 新しいWT窓を開くのを防ぐ(全コンソール窓を非表示にする)。
Dim cmd, i, a
cmd = "conhost.exe ""C:\Program Files\PowerShell\7\pwsh.exe"""
For i = 0 To WScript.Arguments.Count - 1
    a = WScript.Arguments(i)
    If InStr(a, " ") > 0 Then
        cmd = cmd & " """ & a & """"
    Else
        cmd = cmd & " " & a
    End If
Next
' 第2引数 0 = 非表示ウィンドウ, 第3引数 False = 完了を待たずに即リターン
CreateObject("WScript.Shell").Run cmd, 0, False
