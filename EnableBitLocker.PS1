# Enable BitLocker script
# Last change: 4/8/21 - Added 2 lines around line 40 to hopefully save recovery keys to Azure AD.


$LogFile = "$env:systemroot\Temp\EnableBitLocker.log"


$BitLockerDrives = Get-BitLockerVolume
If($BitLockerDrives -eq $null){
    $BLSysPart = Get-Partition -ErrorAction SilentlyContinue | Where-Object {(-not $_.DriveLetter) -and ($_.IsSystem -eq $true)}
    If($BLSysPart -eq $null){
        ShrinkCdrive
    }
    Else{
        $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Output "$TimeStamp No drives available that can be protected with BitLocker." | Tee-Object -FilePath $LogFile -Append
        Write-Output "$TimeStamp Exiting with error 22" | Tee-Object -FilePath $LogFile -Append
        exit 22
    }
}

# If BitLocker can be enabled for C:, do it
$Cdrive = $BitLockerDrives | Where-Object {$_.MountPoint -eq "C:"}
If($Cdrive.Count -ne 1){
    $BLSysPart = Get-Partition -ErrorAction SilentlyContinue | Where-Object {(-not $_.DriveLetter) -and ($_.IsSystem -eq $true)}
    If($BLSysPart -eq $null){
        ShrinkCdrive
    }
    Else{
        Write-Output "No drives available that can be protected with BitLocker." | Tee-Object -FilePath $LogFile -Append
        Write-Output "Exiting with error 22" | Tee-Object -FilePath $LogFile -Append
        exit 22
    }
}
Else{
	EnableBitLocker
}


#get recovery keys and save them to Azure AD ??
$key = manage-bde -protectors -get c:
manage-bde -protectors -aadbackup C: $key



# If other fixed drives found where BitLocker can be enabled, do it
#$OtherDrives = $BitLockerDrives | Where-Object {$_.MountPoint -ne "C:"}
#ForEach($Drive in $OtherDrives){
#    $DriveMP = $Drive.MountPoint
#    $DriveLetter = $DriveMP.Substring(0,1)
#
#    $VolumeInfo = Get-Volume $DriveLetter
#    If($VolumeInfo.DriveType -eq "Fixed"){
#        EnableBitLocker $DriveMP
#    }
#}


Function EnableBitLocker($MountPoint){
    $BLStatus = (Get-BitLockerVolume -MountPoint $MountPoint).VolumeStatus
    $BLProtection = (Get-BitLockerVolume -MountPoint $MountPoint).ProtectionStatus

    # If BitLocker not already on, enable it
    If(($BLStatus -eq "FullyDecrypted") -or ($BLProtection -eq "Off")){
        Try{
            If($MountPoint -eq "C:"){
                $EnableBitLocker = Enable-BitLocker $MountPoint -EncryptionMethod Aes256 -RecoveryPasswordProtector -SkipHardwareTest -ErrorAction Stop
            }
            Else{
                $EnableBitLocker = Enable-BitLocker $MountPoint -EncryptionMethod Aes256 -RecoveryPasswordProtector -ErrorAction Stop
                $EnableBLAutoUnlock = Enable-BitLockerAutoUnlock $MountPoint -ErrorAction Stop
            }
        }
        Catch{
            $ErrorMessage = $_.Exception.Message

            $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Write-Output "$TimeStamp Failed to enable BitLocker for $MountPoint drive, error: $ErrorMessage" | Tee-Object -FilePath $LogFile -Append

            If($ErrorMessage -like "*TPM*"){
                $ErrorNro = 99
            }
            ElseIf($ErrorMessage -like "*DVD*"){
                $ErrorNro = 98
            }
            ElseIf($ErrorMessage -like "*SRK*"){
                $ErrorNro = 96
            }
            Else{
                $ErrorNro = 90
            }

            Write-Output "$TimeStamp Exiting with error $ErrorNro" | Tee-Object -FilePath $LogFile -Append
            exit $ErrorNro
        }
    }
    Else{
        Write-Output "$TimeStamp BitLocker already enabled for $MountPoint" | Tee-Object -FilePath $LogFile -Append
    }

    # Check if BitLocker encryption has started, if not, exit with error
    $BLStatus = (Get-BitLockerVolume -MountPoint $MountPoint).VolumeStatus
    If($BLStatus -eq "FullyDecrypted"){
        $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Output "$TimeStamp Enabling BitLocker for $MountPoint drive has failed for unknown reason" | Tee-Object -FilePath $LogFile -Append
        Write-Output "$TimeStamp Exiting with error 88" | Tee-Object -FilePath $LogFile -Append
        exit 88
    }
    Else{
        $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Output "$TimeStamp Enabled BitLocker for $MountPoint drive successfully" | Tee-Object -FilePath $LogFile -Append        
    }
}
Function ShrinkCdrive{
    cmd /c "C:\Windows\system32\BdeHdCfg.exe" -target %SystemDrive% shrink -quiet
    If($LASTEXITCODE -ne 0){
        $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Output "$TimeStamp Shrinking C: drive for creating system partition for BitLocker failed. Please check manually!" | Tee-Object -FilePath $LogFile -Append
        exit 23
    }
    Else{
        $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Output "$TimeStamp C: drive shrink done to create system partition for BitLocker. Resend the package after reboot." | Tee-Object -FilePath $LogFile -Append
        exit 20
    }
}
