
# when i need my stuff on a fresh win install
# irm x.gd/br_setup |iex

Invoke-WebRequest x.gd/scutl2 | Invoke-Expression # scutl

Get-AppxPackage | Remove-AppxPackage # uwp debloat
scoop install winget

winget install -y Microsoft.WindowsCamera_8wekyb3d8bbwe Microsoft.ScreenSketch_8wekyb3d8bbwe Microsoft.WindowsTerminal_8wekyb3d8bbwe


scoop install brave vscode python spotify discord neovim # apps


Invoke-WebRequest x.gd/12alga | Invoke-Expression # algo


s off
