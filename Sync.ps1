$DEBUG = $false
$LOG = $true
$LogPath = "C:\tmp\synclog.txt"
$FreeFileSyncPath = "C:\Program Files\FreeFileSync\FreeFileSync.exe"
$JobPath = "C:\Users\Administrator\Desktop\BESTA - DatenserverAufNAS Sync.ffs_batch"
$JobName = "DatenserverAufNas"

# cleanup
if ($LOG) {
    if (Test-Path $LogPath) {
        Remove-Item $LogPath
    }
}

# Print :: Print's the given $msg if $DEBUG mode is enabled
function Print($msg) {
	if ($DEBUG) {
		Write-Host $msg
	}
}

# custom logger
function Write-Log {
    Param
    (
        $text
    )

    if ($LOG) {
        "$(get-date -format "yyyy-MM-dd HH:mm:ss"): $($text)" | out-file $LogPath -Append
    }
}

# SendMail :: Construct and send the mail.
#			  Only invoked if the disk space is smaller (or equal) to the defined limit.
#
function SendMail {	
	# Define some variables for futher usag and make it more readable.
    $MailFrom = $Settings.Config.Mail.From
    $MailTo = $Settings.Config.Mail.To
	$CustomerName = $Settings.Config.Customer.Name
	$CustomerServer = $Settings.Config.Customer.Server
    $Username = $Settings.Config.Mail.Credentials.Username
    $Password = $Settings.Config.Mail.Credentials.Password
    $SmtpServer = $Settings.Config.Mail.Server
    $SmtpPort = $Settings.Config.Mail.Port

	# Debug output
	Print("`nMail information")
	Print("From: $MailFrom")
	Print("To: $MailTo")
	Print("Customer: $CustomerName")
	Print("Server: $CustomerServer")
	Print("Username: $Username")
	Print("SmtpServer: $SmtpServer : $SmtpPort")

    $Message = New-Object System.Net.Mail.MailMessage $MailFrom,$MailTo
    $Message.Subject = "[$JobStatus] $JobName - $CustomerName ($CustomerServer)"
	$Message.IsBodyHTML = $false

    
	$Message.Body = $msgText
    Print("Message: $msgText")

    if ($Settings.Config.Log.AppendLog -eq "true") {
        $SyncLogPath = $Settings.Config.Log.Path
        $SyncLogFile = Get-ChildItem -Path $Settings.Config.Log.Path -Attributes !Directory *.html | Sort-Object -Descending -Property LastWriteTime | select -First 1
        $Message.Attachments.Add($SyncLogPath+"\"+$SyncLogFile)
        Print("Log: "+$SyncLogPath+"\"+$SyncLogFile)
        Write-Log -text "FreeFileSyncLog appended, adding scriptlog..."
        $Message.Attachments.Add($LogPath)
    }
    # Construct the SMTP client object, credentials, and send
    $Smtp = New-Object Net.Mail.SmtpClient($SmtpServer,$SmtpPort)
    $Smtp.EnableSsl = $true
    $Smtp.Credentials = New-Object System.Net.NetworkCredential($Username, $Password)
	$Smtp.Send($Message)
}

# Construct the config path and try to load the configuration file
$ConfigPath = $env:LOCALAPPDATA + "\SyncConfig.xml"
try {
	[XML] $Settings = Get-Content -Path $ConfigPath -ErrorAction 'Stop'
    Write-Log -text "Settings loaded from: $ConfigPath"
} catch {
	Write-Host "Could not parse config file ($ConfigPath). Make sure the file exists and you have the right permission to read it." -ForegroundColor red -BackgroundColor black
	exit $LASTEXITCODE 
}


Write-Log -text "Running sync job ($JobPath)..."
# Run the SyncJob and wait for it to finish
$process = Start-Process -FilePath "$FreeFileSyncPath" -ArgumentList `"$JobPath`" -Wait -PassThru
$exitcode = [string]$process.ExitCode
Write-Log -text "FreeFileSync returned with exit code: $exitcode"

switch ($process.ExitCode) {
    0 {
        $JobStatus = "SUCCESS"
        $msgText = $Settings.Config.Status.Ok.Text
    } 1 {
        $JobStatus = "WARNING" 
        $msgText = $Settings.Config.Status.Warning.Text
    } 2 { 
        $JobStatus = "ERROR"
        $msgText = $Settings.Config.Status.Error.Text
    } 3 {
        $JobStatus = "ABORTED"
        $msgText = $Settings.Config.Status.Aborted.Text
    } Default {
        $JobStatus = "ERROR"
        $msgText = "Ein Fehler ist aufgetreten"
    }
}
Write-Log -text "FreeFileSync returned with status code: $JobStatus"
Print($JobStatus)

SendMail
