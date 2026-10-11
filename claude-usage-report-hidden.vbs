' Launches the sibling claude-usage-report.ps1 fully hidden. wscript.exe is a GUI-subsystem
' host, so (unlike powershell.exe -WindowStyle Hidden) it is never handed off to Windows
' Terminal as the default console host, which otherwise flashes a window regardless of
' -WindowStyle. Any arguments passed to this script (e.g. "-Background") are forwarded as-is.
Dim fso, shell, scriptDir, cmd, i
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & scriptDir & "\claude-usage-report.ps1"""
For i = 0 To WScript.Arguments.Count - 1
    cmd = cmd & " " & WScript.Arguments(i)
Next
shell.Run cmd, 0, False
