function New-CDriveExecutionContext {
    param(
        [object[]]$Targets,
        [string[]]$SelectedIds,
        [bool]$IsElevated,
        $Journal = $null
    )

    $catalog = @{}
    foreach ($target in @($Targets)) {
        $id = [string]$target.Id
        if ([string]::IsNullOrWhiteSpace($id) -or $catalog.ContainsKey($id)) { throw 'Execution catalog contains an invalid or duplicate stable ID.' }
        $catalog[$id] = $target
    }
    $selection = @{}
    foreach ($id in @($SelectedIds)) {
        if (-not $catalog.ContainsKey([string]$id)) { throw "[BROKER_UNKNOWN_ID] Unknown cleanup item ID: $id" }
        $selection[[string]$id] = $true
    }
    if ($selection.Count -eq 0) { throw '[BROKER_EMPTY_PLAN] Cleanup requires at least one selected stable ID.' }

    $hasRecycleBin = $selection.ContainsKey('recycle-bin')
    $hasRecoverableContent = @($selection.Keys | Where-Object { [bool]$catalog[$_].UserContent }).Count -gt 0
    if ($hasRecycleBin -and $hasRecoverableContent) {
        throw '[BROKER_RECOVERY_CONFLICT] User content and recycle-bin cleanup must run in separate operations.'
    }

    return [PSCustomObject]@{
        Catalog = $catalog
        SelectedIds = $selection
        IsElevated = $IsElevated
        Journal = $Journal
        RecoveryPolicy = 'user-content-to-recycle-bin'
    }
}

function Get-CDriveRecoverableContentPaths {
    param($Target)

    $paths = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Path -LiteralPath ([string]$Target.Path) -PathType Container)) { return $paths.ToArray() }
    foreach ($account in @(Get-ChildItem -LiteralPath ([string]$Target.Path) -Directory -Force -ErrorAction SilentlyContinue)) {
        if ((([int]$account.Attributes -band 0x400) -ne 0)) { continue }
        foreach ($relative in @(([string]$Target.SubDirs -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
            $candidate = Join-Path $account.FullName $relative
            if (-not (Test-Path -LiteralPath $candidate -PathType Container)) { continue }
            $fullAccount = [System.IO.Path]::GetFullPath($account.FullName).TrimEnd('\') + '\'
            $fullCandidate = [System.IO.Path]::GetFullPath($candidate).TrimEnd('\') + '\'
            if (-not $fullCandidate.StartsWith($fullAccount, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            $paths.Add($candidate)
        }
    }
    return $paths.ToArray()
}

function Invoke-CDriveRecoverableContentCleanup {
    param($Target, [switch]$WhatIf)

    if ([string]$Target.Type -ne 'PatternCache' -or -not [bool]$Target.UserContent) {
        throw '[BROKER_RECOVERY_POLICY] Recoverable cleanup only supports cataloged user-content PatternCache items.'
    }
    Add-Type -AssemblyName Microsoft.VisualBasic
    $staged = 0.0
    $failed = 0
    foreach ($contentRoot in @(Get-CDriveRecoverableContentPaths $Target)) {
        foreach ($item in @(Get-ChildItem -LiteralPath $contentRoot -Force -ErrorAction SilentlyContinue)) {
            if ((([int]$item.Attributes -band 0x400) -ne 0)) { $failed++; continue }
            try {
                if (Get-Command Measure-CDrivePathSize -ErrorAction SilentlyContinue) {
                    $staged += [double](Measure-CDrivePathSize $item.FullName).Size
                } elseif (-not $item.PSIsContainer) {
                    $staged += [double]$item.Length
                }
                if (-not $WhatIf) {
                    if ($item.PSIsContainer) {
                        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
                            $item.FullName,
                            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
                        )
                    } else {
                        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                            $item.FullName,
                            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
                        )
                    }
                }
            } catch {
                $failed++
            }
        }
    }
    return [PSCustomObject]@{ Size = 0.0; Freed = 0.0; StagedForRecovery = $staged; Failed = $failed; Detected = $false; Hint = ''; Note = 'Moved to the Windows Recycle Bin and recoverable until it is emptied.' }
}

function Invoke-CDriveBrokeredCleanup {
    param(
        $Context,
        [string]$ItemId,
        [System.Collections.IDictionary]$Handlers,
        [switch]$WhatIf
    )

    if ($null -eq $Context -or -not $Context.SelectedIds.ContainsKey($ItemId)) {
        throw "[BROKER_NOT_SELECTED] Cleanup item was not selected in the validated plan: $ItemId"
    }
    $target = $Context.Catalog[$ItemId]
    if ($null -eq $target) { throw "[BROKER_UNKNOWN_ID] Cleanup item is not in the execution catalog: $ItemId" }
    if ([string]$target.Type -in @('Detect', 'SpaceHog')) { throw "[BROKER_DIAGNOSTIC_ONLY] Item cannot execute cleanup: $ItemId" }

    $mode = if ([bool]$target.UserContent) { 'recycle-bin' } else { 'permanent-cache-cleanup' }
    Write-CDriveJournalItemStarted $Context.Journal $ItemId $mode
    if ([bool]$target.RequiresAdmin -and -not [bool]$Context.IsElevated) {
        Write-CDriveJournalItemCompleted $Context.Journal $ItemId 'skipped' 0 0 0 'REQUIRES_ADMIN'
        return [PSCustomObject]@{ Size = 0.0; Freed = 0.0; StagedForRecovery = 0.0; Failed = 0; Detected = $false; Hint = ''; Note = 'Requires administrator rights; automatic elevation is disabled, so the item was skipped.'; Status = 'skipped' }
    }

    try {
        if ([bool]$target.UserContent) {
            $result = Invoke-CDriveRecoverableContentCleanup $target -WhatIf:$WhatIf
        } elseif ($WhatIf) {
            $result = [PSCustomObject]@{ Size = 0.0; Freed = 0.0; StagedForRecovery = 0.0; Failed = 0; Detected = $false; Hint = ''; Note = 'WhatIf' }
        } else {
            $handler = $Handlers[[string]$target.Type]
            if ($null -eq $handler) { throw "No cleanup handler for catalog type: $($target.Type)" }
            $result = & $handler $target 'clean'
            if ($null -eq $result) { throw 'Cleanup handler returned no result.' }
            if ($null -eq $result.PSObject.Properties['StagedForRecovery']) { $result | Add-Member -NotePropertyName StagedForRecovery -NotePropertyValue 0.0 }
        }
        $status = if ([int]$result.Failed -gt 0) { 'failed' } else { 'completed' }
        Write-CDriveJournalItemCompleted $Context.Journal $ItemId $status ([double]$result.Freed) ([double]$result.StagedForRecovery) ([int]$result.Failed) ''
        $result | Add-Member -NotePropertyName Status -NotePropertyValue $status -Force
        return $result
    } catch {
        Write-CDriveJournalItemCompleted $Context.Journal $ItemId 'failed' 0 0 1 'BROKER_EXECUTION_FAILED'
        return [PSCustomObject]@{ Size = 0.0; Freed = 0.0; StagedForRecovery = 0.0; Failed = 1; Detected = $false; Hint = ''; Note = $_.Exception.Message; Status = 'failed' }
    }
}
