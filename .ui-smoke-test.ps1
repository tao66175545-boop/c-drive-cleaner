$uiScriptPath = Join-Path $PSScriptRoot 'C-Drive-Cleaner-UI.ps1'
$uiSource = [System.IO.File]::ReadAllText($uiScriptPath, [System.Text.Encoding]::UTF8)
if ($uiSource -match 'CDriveRoundedButton\s*:\s*Button|\.FlatStyle|\.FlatAppearance|UseVisualStyleBackColor') {
    throw 'Button regression: detected WinForms Button rendering residue.'
}
if ($uiSource -notmatch 'CDriveRoundedButton\s*:\s*Control') {
    throw 'Button regression: independent Control implementation is missing.'
}
if ($uiSource -notmatch '\$logoAnimationDurationMs\s*=\s*2220' -or
    $uiSource -notmatch 'System\.Diagnostics\.Stopwatch' -or
    $uiSource -notmatch 'Elapsed\.TotalMilliseconds' -or
    $uiSource -match '\$logoAnimationTimer\.Interval\s*=\s*100') {
    throw 'Logo animation regression: source-timeline playback is missing.'
}
if ($uiSource -notmatch '\$logoStaticImage\s*=\s*\$logoFrames\[\$logoFrames\.Count\s*-\s*1\]' -or $uiSource -notmatch '\$brandLogo\.Image\s*=\s*\$logoStaticImage') {
    throw 'Logo regression: a complete static rest state is missing.'
}
if ($uiSource -notmatch '\$contentHost\.Controls\.AddRange' -or $uiSource -notmatch '\$contentHost\.Location') {
    throw 'Layout regression: content host separation is missing.'
}
if ($uiSource -notmatch 'SelectionOutput|SelectionFile|Show-CleanupSelection|New-SelectedCleanupFile') {
    throw 'Selection workflow regression: scan-to-selection pipeline is missing.'
}
if ($uiSource -notmatch '\$userContentWarning' -or $uiSource -notmatch 'FileRecv') {
    throw 'User-media confirmation regression: the explicit warning is missing.'
}
if ($uiSource -notmatch 'Invoke-CDriveAssistantTool' -or $uiSource -notmatch '\$navAssistant' -or
    $uiSource -notmatch 'LastProposedIds' -or $uiSource -notmatch '\$btnAssistantApply\.Add_Click') {
    throw 'Assistant UI regression: constrained tool routing or confirmation boundary is missing.'
}
if ($uiSource -notmatch "'-SkipProfile'" -or $uiSource -notmatch "'scan\.provider\.selected'" -or $uiSource -notmatch "'scan\.incremental\.completed'") {
    throw 'Incremental scan UI regression: fast scan arguments or provider events are missing.'
}
if ($uiSource -notmatch '\$exitCode' -or $uiSource -notmatch '\$succeeded') {
    throw 'Job status regression: engine exit codes are not handled.'
}

$replacement = @'
$form.Show()
[System.Windows.Forms.Application]::DoEvents()

function Get-ButtonSurfacePixel($Button) {
    $image = [System.Drawing.Bitmap]::new($Button.Width, $Button.Height)
    $Button.DrawToBitmap($image, [System.Drawing.Rectangle]::new(0, 0, $image.Width, $image.Height))
    $pixel = $image.GetPixel(10, [Math]::Floor($Button.Height / 2))
    $image.Dispose()
    return $pixel
}
function Assert-ButtonSurface($Button, $Expected, [string]$State) {
    $actual = Get-ButtonSurfacePixel $Button
    if ($actual.ToArgb() -ne $Expected.ToArgb()) {
        throw ('Button {0} has an incorrect {1} surface: expected {2}, actual {3}' -f $Button.Text, $State, $Expected, $actual)
    }
}
function Invoke-ButtonLifecycle($Button, [string]$Method, [object[]]$Arguments) {
    $flags = [System.Reflection.BindingFlags]'Instance,NonPublic'
    $callback = [CDriveRoundedButton].GetMethod($Method, $flags)
    if ($null -eq $callback) { throw ('Button state handler is missing: ' + $Method) }
    [void]$callback.Invoke($Button, $Arguments)
}

$allButtons = @($navOverview, $navLogs, $navSelection, $navAssistant, $btnScan, $btnReport, $btnClean, $btnExit, $btnAssistantSettings, $btnAssistantStop, $btnAssistantApply, $btnAssistantSend)
foreach ($button in $allButtons) {
    if ($button.GetType().BaseType -ne [System.Windows.Forms.Control]) {
        throw ('Incorrect button base class: ' + $button.Text)
    }
    if ($button.CornerRadius -ne 8) { throw ('Incorrect button radius token: ' + $button.Text) }
}

Assert-ButtonSurface $btnReport $btnReport.BackColor '默认'
Invoke-ButtonLifecycle $btnReport 'OnMouseEnter' @([EventArgs]::Empty)
Assert-ButtonSurface $btnReport $btnReport.HoverBackColor '悬停'
Invoke-ButtonLifecycle $btnReport 'OnMouseDown' @([System.Windows.Forms.MouseEventArgs]::new([System.Windows.Forms.MouseButtons]::Left, 1, 10, 18, 0))
Assert-ButtonSurface $btnReport $btnReport.PressedBackColor '按下'
Invoke-ButtonLifecycle $btnReport 'OnMouseUp' @([System.Windows.Forms.MouseEventArgs]::new([System.Windows.Forms.MouseButtons]::Left, 1, 10, 18, 0))
Assert-ButtonSurface $btnReport $btnReport.HoverBackColor '释放'
Invoke-ButtonLifecycle $btnReport 'OnMouseLeave' @([EventArgs]::Empty)
Assert-ButtonSurface $btnReport $btnReport.BackColor '离开'
Assert-ButtonSurface $navOverview $navOverview.SelectedBackColor '选中'
$btnScan.Enabled = $false
Assert-ButtonSurface $btnScan ([System.Drawing.Color]::FromArgb(240, 241, 242)) '禁用'
$btnScan.Enabled = $true

if ($logoFrames.Count -ne 135) { throw ('Unexpected logo frame count: ' + $logoFrames.Count) }
if ($null -eq $logoStaticImage -or -not [object]::ReferenceEquals($brandLogo.Image, $logoStaticImage)) { throw 'Logo did not start in its complete static state.' }
if (-not [object]::ReferenceEquals($logoStaticImage, $logoFrames[$logoFrames.Count - 1])) { throw 'Logo rest state differs from its final animation frame.' }
Start-LogoAnimation
Start-Sleep -Milliseconds 90
[System.Windows.Forms.Application]::DoEvents()
if (-not $logoAnimationState.Active -or $logoAnimationState.Index -lt 3) { throw 'Logo animation did not advance by elapsed source time.' }
Stop-LogoAnimation
if (-not [object]::ReferenceEquals($brandLogo.Image, $logoStaticImage)) { throw 'Logo did not restore its complete static state.' }

if ($logContent.Padding.Top -lt 8 -or $logContent.Padding.Left -lt 8) { throw 'Log output has insufficient internal padding.' }
if ($dashboardGrid.RowStyles[0].Height -lt 100) { throw 'Statistic row height is insufficient.' }

$selectionFixturePath = Join-Path $env:TEMP ('cdc-ui-selection-fixture-{0}.json' -f [guid]::NewGuid().ToString('N'))
$selectionFixture = [PSCustomObject]@{
    SchemaVersion = 2
    ScanId = [guid]::NewGuid().ToString('N')
    ManifestHash = ('a' * 64)
    ScannedAt = (Get-Date).ToString('o')
    Items = @(
        [PSCustomObject]@{ Id = 'user-temp'; Name = 'User temporary files'; Type = 'FolderContents'; Path = 'C:\Temp'; Size = 52428800; Recommendation = 'Recommended'; RecommendationLevel = 'Recommended'; Advice = 'Can be recreated safely.'; Note = '' },
        [PSCustomObject]@{ Id = 'user-wechat-media'; Name = 'WeChat media attachments'; Type = 'PatternCache'; Path = 'C:\Users\Example\Documents\WeChat Files\Example\FileStorage\Image'; Size = 10485760; Recommendation = 'Review'; RecommendationLevel = 'Review'; Advice = 'Irreversible user media.'; Note = ''; SafetyLevel = 'UserContent' }
    )
}
[System.IO.File]::WriteAllText($selectionFixturePath, ($selectionFixture | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
Show-CleanupSelection $selectionFixturePath
if ($dashboardState.SelectionItems.Count -ne 2 -or $navigationState.View -ne 'selection') { throw 'Selection screen did not load scanned items.' }
if ($contentHost.Top -ne $topBar.Bottom -or $contentHost.ClientSize.Height -lt 1) { throw 'Content host is not positioned below the top bar.' }
if ([Math]::Abs(($btnSelectSuggested.Top * 2 + $btnSelectSuggested.Height) - $selectionActionBar.ClientSize.Height) -gt 1) { throw 'Suggested-selection button is not vertically centered.' }
if ([Math]::Abs(($btnClearSelection.Top * 2 + $btnClearSelection.Height) - $selectionActionBar.ClientSize.Height) -gt 1) { throw 'Clear-selection button is not vertically centered.' }
$selectionRows = @($selectionItemsPanel.Controls | Where-Object { $_ -is [CDriveRoundedPanel] -and $null -ne $_.Tag.SizeLabel })
if ($selectionRows.Count -ne 2) { throw 'Selection row components were not created for every scanned item.' }
foreach ($row in $selectionRows) {
    $sizeLabel = $row.Tag.SizeLabel
    if ($sizeLabel.Top -lt 8) { throw 'Selection row size label intrudes into the rounded top-edge safe area.' }
    $rightInset = $row.ClientSize.Width - $sizeLabel.Right
    if ($rightInset -ne 14) { throw ('Selection row size label right inset is inconsistent: ' + $rightInset) }
    if ($sizeLabel.BackColor.A -ne 0) { throw 'Selection row size label must keep the rounded card surface visible.' }

    $rowPreview = [System.Drawing.Bitmap]::new($row.Width, $row.Height)
    try {
        $row.DrawToBitmap($rowPreview, [System.Drawing.Rectangle]::new(0, 0, $rowPreview.Width, $rowPreview.Height))
        $edgePixel = $rowPreview.GetPixel([Math]::Floor($sizeLabel.Left + ($sizeLabel.Width / 2)), 0)
        if ($edgePixel.ToArgb() -eq [System.Drawing.Color]::White.ToArgb()) {
            throw 'Selection row top border is obscured above the size label.'
        }
    } finally {
        $rowPreview.Dispose()
    }
}
if ($btnClean.Enabled) { throw 'Clean action must remain disabled before user selection.' }
$onClick = [CDriveRoundedButton].GetMethod('OnClick', [System.Reflection.BindingFlags]'Instance,NonPublic')
[void]$onClick.Invoke($btnSelectSuggested, [object[]]@([EventArgs]::Empty))
if ($dashboardState.SelectedIds.Count -ne 1 -or -not $btnClean.Enabled) { throw 'Suggested selection did not enable the scoped clean action.' }
if ($dashboardState.SelectedIds.ContainsKey('user-wechat-media')) { throw 'Suggested selection must not include user media.' }
Set-DashboardView 'assistant'
$assistantState.Config = $null
$assistantInput.Text = 'recommend safe cleanup'
Invoke-AssistantQuery
if ($navigationState.View -ne 'assistant' -or @($assistantState.LastProposedIds).Count -ne 1) { throw 'Assistant did not produce a constrained proposal.' }
if ($assistantState.LastProposedIds[0] -ne 'user-temp' -or -not $btnAssistantApply.Enabled) { throw 'Assistant proposal crossed the stable-ID or risk boundary.' }
$agentFixtureRoot = Join-Path $env:TEMP ('cdc-ui-agent-fixture-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $agentFixtureRoot -Force | Out-Null
$agentDataRoot = $agentFixtureRoot
$agentConfigPath = Join-Path $agentFixtureRoot 'provider.json'
$agentConfig = [PSCustomObject]@{ schemaVersion = 1; providerId = 'fixture-provider'; protocol = 'chat-completions'; baseUrl = 'https://api.example.com/v1'; model = 'fixture-model'; stream = $true; timeoutSeconds = 30; maxOutputTokens = 512; credentialId = 'fixture'; cloudConsent = $null }
$agentConfig = Grant-CDriveAgentCloudConsent $agentConfig
$null = Save-CDriveAgentConfig $agentConfig $agentConfigPath
$assistantState.Config = $agentConfig
$agentSsePath = Join-Path $agentFixtureRoot 'response.sse'
[System.IO.File]::WriteAllLines($agentSsePath, @(
    'data: {"choices":[{"delta":{"content":"Fixture "}}]}',
    'data: {"choices":[{"delta":{"content":"stream complete."}}]}',
    'data: [DONE]'
), [System.Text.UTF8Encoding]::new($false))
$assistantState.FixtureSsePath = $agentSsePath
$assistantInput.Text = 'summarize current scan'
Invoke-AssistantQuery
$agentDeadline = [DateTime]::UtcNow.AddSeconds(8)
while ($assistantState.Process -and [DateTime]::UtcNow -lt $agentDeadline) {
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 20
}
if ($assistantState.Process) { throw 'Fixture Agent did not complete without blocking the UI.' }
if ($assistantTranscript.Text -notmatch 'Fixture stream complete\.') { throw ('Fixture Agent stream was not rendered in the assistant transcript. Transcript: ' + $assistantTranscript.Text) }
$assistantState.FixtureSsePath = ''
$navCall = [PSCustomObject]@{ callId = 'ui_fixture_nav'; name = 'navigate_view'; argumentsJson = '{"view":"overview"}' }
$navResult = Invoke-AgentUiTool $navCall
if ($navResult.view -ne 'overview' -or $navigationState.View -ne 'overview') { throw 'Agent UI tool did not navigate through the broker.' }
try { $null = Invoke-AgentUiTool $navCall; throw 'Agent UI replay was accepted.' }
catch { if ($_.Exception.Message -notmatch 'AGENT_TOOL_REPLAY') { throw } }
Set-DashboardView 'assistant'
$assistantPreview = [System.Drawing.Bitmap]::new($form.ClientSize.Width, $form.ClientSize.Height)
$form.DrawToBitmap($assistantPreview, [System.Drawing.Rectangle]::new(0, 0, $assistantPreview.Width, $assistantPreview.Height))
$assistantPreview.Save((Join-Path (Get-Location) 'ui-assistant-preview.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$assistantPreview.Dispose()
[void]$onClick.Invoke($btnAssistantApply, [object[]]@([EventArgs]::Empty))
if ($navigationState.View -ne 'selection' -or $dashboardState.SelectedIds.Count -ne 1 -or -not $dashboardState.SelectedIds.ContainsKey('user-temp')) { throw 'Assistant did not apply reversible UI selection state.' }
$selectionPreview = [System.Drawing.Bitmap]::new($form.ClientSize.Width, $form.ClientSize.Height)
$form.DrawToBitmap($selectionPreview, [System.Drawing.Rectangle]::new(0, 0, $selectionPreview.Width, $selectionPreview.Height))
$selectionPreview.Save((Join-Path (Get-Location) 'ui-selection-preview.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$selectionPreview.Dispose()

$preview = [System.Drawing.Bitmap]::new($form.ClientSize.Width, $form.ClientSize.Height)
$form.DrawToBitmap($preview, [System.Drawing.Rectangle]::new(0, 0, $preview.Width, $preview.Height))
$preview.Save((Join-Path (Get-Location) 'ui-preview.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$preview.Dispose()
Set-DashboardView 'logs'
[System.Windows.Forms.Application]::DoEvents()
if ($contentHost.Top -ne $topBar.Bottom -or $dashboardGrid.Top -ne 0) { throw 'Log view overlaps the top bar after navigation.' }
$logsPreview = [System.Drawing.Bitmap]::new($form.ClientSize.Width, $form.ClientSize.Height)
$form.DrawToBitmap($logsPreview, [System.Drawing.Rectangle]::new(0, 0, $logsPreview.Width, $logsPreview.Height))
$logsPreview.Save((Join-Path (Get-Location) 'ui-logs-preview.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$logsPreview.Dispose()
Set-DashboardView 'overview'
[System.Windows.Forms.Application]::DoEvents()
if ($contentHost.Top -ne $topBar.Bottom -or $statCards[0].Panel.Top -lt 0) { throw 'Overview overlaps the top bar after navigation.' }
$form.Size = [System.Drawing.Size]::new(1060, 680)
[System.Windows.Forms.Application]::DoEvents()
$compactPreview = [System.Drawing.Bitmap]::new($form.ClientSize.Width, $form.ClientSize.Height)
$form.DrawToBitmap($compactPreview, [System.Drawing.Rectangle]::new(0, 0, $compactPreview.Width, $compactPreview.Height))
$compactPreview.Save((Join-Path (Get-Location) 'ui-compact-preview.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$compactPreview.Dispose()
$form.Close()
$form.Dispose()
if (Test-Path -LiteralPath $selectionFixturePath) { [System.IO.File]::Delete($selectionFixturePath) }
if (Test-Path -LiteralPath $agentFixtureRoot) { Remove-Item -LiteralPath $agentFixtureRoot -Recurse -Force }
'@
$uiSource = $uiSource.Replace('[void]$form.ShowDialog()', $replacement)
Invoke-Expression $uiSource
