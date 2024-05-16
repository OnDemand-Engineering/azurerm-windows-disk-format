<#
    .DESCRIPTION
    Disk formatting Script
#>

Param (        
    [Parameter(Mandatory = $false)]
    [ValidateNotNullorEmpty()] 
    [string] $diskConfig
)

begin {
    function Write-Log {
        [CmdletBinding()]
        <#
            .SYNOPSIS
            Create log function
        #>
        param (
            [Parameter(Mandatory = $True)]
            [ValidateNotNullOrEmpty()]
            [System.String] $logPath,
        
            [Parameter(Mandatory = $True)]
            [ValidateNotNullOrEmpty()]
            [System.String] $object,
        
            [Parameter(Mandatory = $True)]
            [ValidateNotNullOrEmpty()]
            [System.String] $message,
        
            [Parameter(Mandatory = $True)]
            [ValidateNotNullOrEmpty()]
            [ValidateSet('Information', 'Warning', 'Error', 'Verbose', 'Debug')]
            [System.String] $severity,
        
            [Parameter(Mandatory = $False)]
            [Switch] $toHost
        )
        
        begin {
            $date = (Get-Date).ToLongTimeString()
        }
        process {
            if (($severity -eq "Information") -or ($severity -eq "Warning") -or ($severity -eq "Error") -or ($severity -eq "Verbose" -and $VerbosePreference -ne "SilentlyContinue") -or ($severity -eq "Debug" -and $DebugPreference -ne "SilentlyContinue")) {
                if ($True -eq $toHost) {
                    Write-Host $date -ForegroundColor Cyan -NoNewline
                    Write-Host " - [" -ForegroundColor White -NoNewline
                    Write-Host "$object" -ForegroundColor Yellow -NoNewline
                    Write-Host "] " -ForegroundColor White -NoNewline
                    Write-Host ":: " -ForegroundColor White -NoNewline
        
                    Switch ($severity) {
                        'Information' {
                            Write-Host "$message" -ForegroundColor White
                        }
                        'Warning' {
                            Write-Warning "$message"
                        }
                        'Error' {
                            Write-Host "ERROR: $message" -ForegroundColor Red
                        }
                        'Verbose' {
                            Write-Verbose "$message"
                        }
                        'Debug' {
                            Write-Debug "$message"
                        }
                    }
                }
            }
        
            switch ($severity) {
                "Information" { [int]$type = 1 }
                "Warning" { [int]$type = 2 }
                "Error" { [int]$type = 3 }
                'Verbose' { [int]$type = 2 }
                'Debug' { [int]$type = 2 }
            }
        
            if (!(Test-Path (Split-Path $logPath -Parent))) { New-Item -Path (Split-Path $logPath -Parent) -ItemType Directory -Force | Out-Null }
        
            $content = "<![LOG[$message]LOG]!>" + `
                "<time=`"$(Get-Date -Format "HH:mm:ss.ffffff")`" " + `
                "date=`"$(Get-Date -Format "M-d-yyyy")`" " + `
                "component=`"$object`" " + `
                "context=`"$([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)`" " + `
                "type=`"$type`" " + `
                "thread=`"$([Threading.Thread]::CurrentThread.ManagedThreadId)`" " + `
                "file=`"`">"
            if (($severity -eq "Information") -or ($severity -eq "Warning") -or ($severity -eq "Error") -or ($severity -eq "Verbose" -and $VerbosePreference -ne "SilentlyContinue") -or ($severity -eq "Debug" -and $DebugPreference -ne "SilentlyContinue")) {
                Add-Content -Path $($logPath + ".log") -Value $content
            }
        }
        end {}
    }

    $LogPath = "$env:SYSTEMROOT\TEMP\Deployment_" + (Get-Date -Format 'yyyy-MM-dd')

    # Set Variables
    $diskConfigArray = @()
    foreach ($item in $diskConfig.split(';')) {
        $myObject = [PSCustomObject]@{
            driveLetter = $item.split(',')[0]
            volumeLabel = $item.split(',')[1]
        }
        $diskConfigArray += $myObject
    }
}

process {
    # Dismount any attached ISOs
    Get-Volume | Where-Object {$_.DriveType -eq "CD-ROM"} | Get-DiskImage | Dismount-DiskImage

    # Initialize and format Data Disks
    [array]$DataDisks = Get-Disk | Where-Object { ($_.IsSystem -eq $false) -and ($_.PartitionStyle -eq 'RAW') } | Sort-Object Number
    if ($DataDisks) {
        foreach ($Disk in $DataDisks) {
            $usedDriveLetters = (Get-Volume).DriveLetter | Sort-Object
            if ($usedDriveLetters -notcontains $diskConfigArray[[array]::IndexOf($dataDisks, $disk)].driveLetter) {
                $driveLetter = $diskConfigArray[[array]::IndexOf($dataDisks, $disk)].driveLetter
            }
            else {
                $driveLetter = 'EFGHIJKLMNOPQRSTUVWXY' -replace ("$($diskConfigArray.DriveLetter -join '|')", '') -split '' | Where-Object { $_ -notin (Get-CimInstance -ClassName win32_logicaldisk).DeviceID.Substring(0, 1) } | Where-Object { $_ } | Select-Object -first 1
                Write-Log -Object "Disk Formatting" -Message "Drive Letter: $($diskConfigArray[[array]::IndexOf($dataDisks, $disk)].driveLetter) in use, using $driveLetter instead" -Severity Information -LogPath $LogPath
            }
            $Disk | Initialize-Disk -PartitionStyle GPT
            $Partition = $Disk | New-Partition -DriveLetter $driveLetter -UseMaximumSize
            $Partition | Format-Volume -FileSystem NTFS -NewFileSystemLabel $diskConfigArray[[array]::IndexOf($dataDisks, $disk)].volumeLabel
            Write-Log -Object "Disk Formatting" -Message "Formatted disk:$($Disk.Number) driveLetter:$($driveLetter) volumeLabel:$($diskConfigArray[[array]::IndexOf($dataDisks, $disk)].volumeLabel)" -Severity Information -LogPath $LogPath
        }
    }
}