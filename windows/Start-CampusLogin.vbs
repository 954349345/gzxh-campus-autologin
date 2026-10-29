' 静默启动 CampusLogin.ps1（不弹出黑色命令行窗口）
' 由计划任务调用：wscript.exe //nologo Start-CampusLogin.vbs
Option Explicit

Dim fso, shell, dir, cmd
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

dir = fso.GetParentFolderName(WScript.ScriptFullName)

cmd = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File """ _
    & dir & "\CampusLogin.ps1"" -Action auto -Quiet"

shell.Run cmd, 0, False
