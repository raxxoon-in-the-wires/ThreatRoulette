<#
.SYNOPSIS
    Randomized or Manual Threat Actor Emulation using Atomic Red Team.

.DESCRIPTION
    ThreatRoulette selects a random Threat Actor from the pool of downloaded Threat Actor TTPs
    ($MitreTTPsLocation) and randomly selects TTPs which are present in both the AtomicRed Atomics
    folder and the MITRE TTPs for that actor. Alternatively, allows the user to select the Threat Actor and TTPs manually.

    This tool is a wrapper around Atomic Red Team. Atomic Red Team must be installed separately —
    see their repository for installation instructions.

.PARAMETER MitreTTPsLocation
    Specifies the folder location that holds the JSON files corresponding to all relevant Threat Actors.
    To add your own Threat Actor, navigate to the Mitre Att&ck Groups website (https://attack.mitre.org/groups/),
    select the Threat Actor, find the "Techniques Used" section, click the "ATT&CK Navigator Layers" button,
    and download the Enterprise layer.
    Rename the resulting JSON file to this format: [Threat Actor Name]-TTPs.json. Ex. MuddyWater-TTPs.json
    Renaming the file to this format is essential for the text manipulation in this script.

.PARAMETER Atomics
    Specifies the folder location that holds the TTPs for Invoke-AtomicTest testing.

.PARAMETER ConfigRecord
    Specifies the output path for the configuration log file.

.EXAMPLE
    .\ThreatRoulette.ps1 -MitreTTPsLocation "C:\AtomicRed\MitreTTPs" -Atomics "C:\AtomicRed\atomics"

.NOTES
    Author: Everett Porter
    DateCreated: 2026-06-27
    Version: 1.0

.LINK
    ThreatRoulette
    https://github.com/raxxoon-in-the-wires/ThreatRoulette

    Atomic Red Team - Red Canary
    https://github.com/redcanaryco/atomic-red-team
#>

param(
    [string]$MitreTTPsLocation = "C:\AtomicRedTeam\MitreTTPs",
    [string]$Atomics            = "C:\AtomicRedTeam\atomics",
    [ValidateScript({
        try {
            New-Item -Path $_ -ItemType File -Force -ErrorAction Stop | Out-Null
            return $true
        }
        catch {
            throw "Failed to create ConfigRecord at path: $_"
        }
    })]
    [string]$ConfigRecord = "C:\AtomicRedTeam\ConfigRecord_$(Get-Date -Format 'yyyy.MM.dd_HHmm').txt"
)


$AtomicsTests = Get-ChildItem -Path $Atomics -Directory | Select-Object -ExpandProperty Name

$ThreatActors = Get-ChildItem $MitreTTPsLocation |
    Select-Object -ExpandProperty Name |
    ForEach-Object { $_ -replace "-TTPs\.json$", "" }

$techniques = [System.Collections.Generic.List[object]]@()


Clear-Host
Write-Host "`n    #============================================================#"
Write-Host "    |                                                            |"
Write-Host "    |                       ThreatRoulette                       |"
Write-Host "    |                                                            |"
Write-Host "    #============================================================#`n"
Write-Host "`n"
Write-Host "How would you like to run this tool? (Automatic or Manual)`n--------------------------------------------------------------------------------------------------------------------`n`n`t - Automatic: A random threat actor and associated TTPs are selected, then passed to AtomicRed for execution.`n`n`t - Manual: You select the Threat Actor and associated TTPs for AtomicRed execution.`n`n"

do {
    $OperationMode = Read-Host "[OperationMode]"
    if ($OperationMode -eq "A" -or $OperationMode -eq "Automatic" -or
        $OperationMode -eq "M" -or $OperationMode -eq "Manual") { break }
    Write-Host "Invalid selection. Please enter 'Automatic', 'Manual', 'A', or 'M'." -ForegroundColor Red
} while ($true)

Clear-Host
Write-Host "`n    #============================================================#"
Write-Host "    |                                                            |"
Write-Host "    |                       ThreatRoulette                       |"
Write-Host "    |                                                            |"
Write-Host "    #============================================================#"
Write-Host "`n"
Write-Host "How many TTPs would you like to emulate? (Numbers only)" -ForegroundColor Cyan
Write-Host "--------------------------------------------------------------------------------------------------------------------`n"  # FIX: was '`n (literal apostrophe-n, not a newline escape)

do {
    $TargetTTPs = Read-Host "[Number of TTPs]"
    if (($TargetTTPs -as [int]) -ne $null -and [int]$TargetTTPs -gt 0) { break }
    Write-Host "Invalid input. Please enter a positive whole number." -ForegroundColor Red
} while ($true)
$TargetTTPs = [int]$TargetTTPs


function SaveConfig ([string]$text) {
    $text >> $ConfigRecord
}


function ManualConfigThreatActor {
    Write-Host "`nThreat Actor Options"
    Write-Host "--------------------------------------------------------------------------------------------------------------------`n"  # FIX: was '`n
    $i = 0
    foreach ($ta in $ThreatActors) {
        $i = $i + 1
        Write-Host "  $i) $ta"
    }
    Write-Host "`n"
    Write-Host "What Threat Actor would you like to emulate? (Enter either a number or name)" -ForegroundColor Cyan
    Write-Host "--------------------------------------------------------------------------------------------------------------------`n"  # FIX: was '`n
    $ThreatActorSelection = Read-Host "[Threat Actor Selection]"
    Write-Host " "

    if (($ThreatActorSelection -as [int]) -ne $null) {
        Write-Host "Number detected, recalculating..."
        $TAIndex = [int]$ThreatActorSelection
        $ThreatActorSelection = $ThreatActors[$TAIndex - 1]
    }

    if ($ThreatActors -notcontains $ThreatActorSelection) {
        Write-Host "ERROR: Threat Actor not available." -ForegroundColor Red
        Write-Host "Check your spelling/index number, or download the Threat Actor's MITRE file and save it to $MitreTTPsLocation" -ForegroundColor Red
        exit 1
    }

    Clear-Host
    Write-Host "    #============================================================#"
    Write-Host "    |                                                            |  "
    Write-Host "    |             ThreatRoulette Manual Configuration            |"
    Write-Host "    |                                                            |  "
    Write-Host "    #============================================================#"
    Write-Host "    |                                                            |  "
    Write-Host "    |             Threat Actor:      "$ThreatActorSelection.PadRight(19)"       |  "
    Write-Host "    |                                                            |  "
    Write-Host "    |                                                            |  "
    Write-Host "    |                      Confirm Selection?                    |  "
    Write-Host "    |                                                            |  "
    Write-Host "    |             [Y]                              [N]           |  "
    Write-Host "    |                                                            |  "
    Write-Host "    #============================================================#"
    Write-Host "`n"

    $Confirmation = Read-Host "[Confirmation]"

    if ($Confirmation -eq "N") {
        return ManualConfigThreatActor
    }

    return $ThreatActorSelection
}


function ManualConfigTTPs {
    param (
        [string]$ThreatActor
    )

    # Local lists ensure a clean state if the function is called recursively on retry.
    $TTPsList     = [System.Collections.Generic.List[object]]@()
    $SelectedTTPs = [System.Collections.Generic.List[object]]@()

    $ThreatActorJSON = Get-Content "$MitreTTPsLocation\$ThreatActor-TTPs.json" -Raw | ConvertFrom-Json
    $ThreatActorJSON.techniques | ForEach-Object {
        $TTPsList.Add($_.techniqueID)
    }

    Write-Host "`nLoading associated TTPs for $ThreatActor..."
    Write-Host "Comparing available TTPs in atomics folder and removing non-matches..." -ForegroundColor Yellow
    Start-Sleep -Seconds 2

    $TTPsList = [System.Collections.Generic.List[object]](
        $TTPsList | Where-Object { $AtomicsTests -contains $_ }
    )


    Write-Host "`n"
    Write-Host "Threat Actor Associated TTPs" -ForegroundColor Cyan
    Write-Host "--------------------------------------------------------------------------------------------------------------------"

    $halfcount = [Math]::Ceiling($TTPsList.Count / 2)
    for ($i = 0; $i -lt $halfcount; $i++) {
        $rightIndex = $i + $halfcount
        $firstobj   = "`t`t`t$($i + 1)) $($TTPsList[$i].PadRight(9))"
        $secondobj  = if ($rightIndex -lt $TTPsList.Count) { "$($rightIndex + 1)) $($TTPsList[$rightIndex].PadRight(9))" } else { "" }
        Write-Host $firstobj.PadRight(35) $secondobj
    }

    Write-Host "`n`nEnter the TTP ID(s) (ex. T1048, T1053.002) or index number (ex. 1, 35, 88) you'd like to emulate" -ForegroundColor Cyan
    Write-Host "--------------------------------------------------------------------------------------------------------------------`n"

    for ($i = 0; $i -lt $TargetTTPs; $i++) {
        $DesiredTTP = Read-Host "[Technique ID]"
        Write-Host "`nTechnique ID: $DesiredTTP"
        Write-Host "----------------"

        if (($DesiredTTP -as [int]) -ne $null) {
            $TTPIndex = [int]$DesiredTTP - 1
            if ($TTPIndex -lt 0 -or $TTPIndex -ge $TTPsList.Count) {
                Write-Host "ERROR: Index out of range. Please enter a number between 1 and $($TTPsList.Count)." -ForegroundColor Red
                $i--
                continue
            }
            $DesiredTTP = $TTPsList[$TTPIndex]
        }

        if ($TTPsList -notcontains $DesiredTTP) {
            $termination = 0
            while ($termination -eq 0) {
                Write-Host "$DesiredTTP is not traditionally associated with $ThreatActor" -ForegroundColor Yellow
                Write-Host "Would you still like to add this TTP? [Y] [N]"
                $TTPConfirmation = Read-Host "[Confirmation]"

                if ($TTPConfirmation -eq "Y") {
                    Write-Host "Override accepted, TTP added..." -ForegroundColor Green
                    $SelectedTTPs.Add($DesiredTTP)
                    $termination = 1
                }
                elseif ($TTPConfirmation -eq "N") {
                    # Decrement so this TTP slot is re-prompted in the outer for loop
                    $i--
                    $termination = 1
                }
                else {
                    Write-Host "Input invalid: must enter either 'Y' or 'N'"
                }
            }
        }
        else {
            $SelectedTTPs.Add($DesiredTTP)
            Write-Host "Successfully added $DesiredTTP `n " -ForegroundColor Green
        }
    }

    Write-Host "`n`n"
    Write-Host "    #============================================================#"
    Write-Host "    |                                                            | "
    Write-Host "    |             ThreatRoulette Manual Configuration            | "
    Write-Host "    |                                                            | "
    Write-Host "    #============================================================#"
    Write-Host "    |                                                            | "
    Write-Host "    |             Threat Actor:      "$ThreatActor.PadRight(25)" | "
    Write-Host "    |                                                            | "
    Write-Host "    |     TTPs Selected:                                         | "
    foreach ($TTP in $SelectedTTPs) {
        Write-Host "    |                           "$TTP.PadRight(21)"          | "
    }
    Write-Host "    |                                                            | "
    Write-Host "    |                      Confirm Selection?                    | "
    Write-Host "    |                                                            | "
    Write-Host "    |             [Y]                              [N]           | "
    Write-Host "    |                                                            | "
    Write-Host "    #============================================================#"
    Write-Host " "
    $Confirmation = Read-Host "[Confirmation]"

    if ($Confirmation -eq "N") {
        return ManualConfigTTPs -ThreatActor $ThreatActor
    }

    SaveConfig " "
    SaveConfig " "
    SaveConfig "    #============================================================#"
    SaveConfig "    |                                                            |"
    SaveConfig "    |             ThreatRoulette Manual Configuration            |"
    SaveConfig "    |                                                            |"
    SaveConfig "    #============================================================#"
    SaveConfig "    |                                                            |"
    SaveConfig "    |             Threat Actor:      $ThreatActor                   |"
    SaveConfig "    |                                                            |"
    SaveConfig "    |     TTPs Selected:                                         |"
    foreach ($TTP in $SelectedTTPs) {
        SaveConfig "    |                            $($TTP.PadRight(24))        |"
    }
    SaveConfig "    |                                                            |"
    SaveConfig "    |                                                            |"
    SaveConfig "    #============================================================#"

    return $SelectedTTPs
}


function AutoConfigThreatActor {
    $ThreatActor = Get-Random -InputObject $ThreatActors -Count 1
    return $ThreatActor
}


function AutoConfigTTPs {
    param (
        [string]$ThreatActor
    )

    $localTTPsList = [System.Collections.Generic.List[object]]@()

    $ThreatActorJSON = Get-Content "$MitreTTPsLocation\$ThreatActor-TTPs.json" -Raw | ConvertFrom-Json
    $ThreatActorJSON.techniques | ForEach-Object {
        $localTTPsList.Add($_.techniqueID)
    }


    $AvailableTTPs = @($localTTPsList | Where-Object { $AtomicsTests -contains $_ })

    if ($AvailableTTPs.Count -eq 0) {
        Write-Host "ERROR: No TTPs for $ThreatActor were found in the Atomics library." -ForegroundColor Red
        exit 1
    }

    if ($AvailableTTPs.Count -lt $TargetTTPs) {
        Write-Host "WARNING: Only $($AvailableTTPs.Count) matching TTPs available for $ThreatActor (requested $TargetTTPs). Using all available." -ForegroundColor Yellow
        $ConfirmedTTP = $AvailableTTPs
    }
    else {
        $ConfirmedTTP = @($AvailableTTPs | Get-Random -Count $TargetTTPs)
    }

    SaveConfig " "
    SaveConfig " "
    SaveConfig "    #============================================================#"
    SaveConfig "    |                                                            |"
    SaveConfig "    |             ThreatRoulette Automatic Configuration         |"
    SaveConfig "    |                                                            |"
    SaveConfig "    #============================================================#"
    SaveConfig "    |                                                            |"
    SaveConfig "    |             Threat Actor:      $ThreatActor                |"
    SaveConfig "    |                                                            |"
    SaveConfig "    |     TTPs Used:                                             |"
    foreach ($TTP in $ConfirmedTTP) {
        SaveConfig "    |                            $($TTP.PadRight(9))                            |"
    }
    SaveConfig "    |                                                            |"
    SaveConfig "    |                                                            |"
    SaveConfig "    #============================================================#"

    return $ConfirmedTTP
}


if ($OperationMode -eq "A" -or $OperationMode -eq "Automatic") {
    Write-Host "`n    #============================================================#"
    Write-Host "    |                                                            |"
    Write-Host "    |           ThreatRoulette Automatic Configuration           |"
    Write-Host "    |                                                            |"
    Write-Host "    #============================================================#"
    $ThreatActor = AutoConfigThreatActor
    $TTPs = AutoConfigTTPs -ThreatActor $ThreatActor
}
elseif ($OperationMode -eq "M" -or $OperationMode -eq "Manual") {
    Write-Host "`n    #============================================================#"
    Write-Host "    |                                                            |"
    Write-Host "    |            ThreatRoulette Manual Configuration             |"
    Write-Host "    |                                                            |"
    Write-Host "    #============================================================#"
    $ThreatActor = ManualConfigThreatActor
    $TTPs = ManualConfigTTPs -ThreatActor $ThreatActor
}


# Execute Adversary Emulation

foreach ($TTP in $TTPs) {
    $technique = Get-ChildItem "$Atomics\$TTP" -Recurse -Include T*.yaml | Get-AtomicTechnique
    $techniques.Add($technique)
}

foreach ($technique in $techniques) {
    foreach ($atomic in $technique.atomic_tests) {
        if ($atomic.supported_platforms.contains("windows") -and ($atomic.executor -ne "manual")) {
            Invoke-AtomicTest $technique.attack_technique -TestGuids $atomic.auto_generated_guid -GetPrereqs
            Invoke-AtomicTest $technique.attack_technique -TestGuids $atomic.auto_generated_guid
            Start-Sleep 3
            Invoke-AtomicTest $technique.attack_technique -TestGuids $atomic.auto_generated_guid -Cleanup
        }
    }
}
