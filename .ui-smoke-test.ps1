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
if ($uiSource -notmatch '\$versionManifestPath\s*=\s*Join-Path\s+\$scriptDir\s+''version\.json''' -or
    $uiSource -notmatch '\$sideFooter\.Text\s*=\s*''版本号 \{0\}''\s+-f\s+\$displayVersion') {
    throw 'Version label regression: sidebar footer is not bound to version.json.'
}
if ($uiSource -match 'StreamReader\(\$fs,\s*\[System\.Text\.Encoding\]::Default\)' -or
    $uiSource -notmatch 'function Read-CDriveUtf8LogSnapshot' -or
    $uiSource -notmatch 'UTF8Encoding\(\$false,\s*\$true\)') {
    throw 'Log encoding regression: runtime log snapshots must use strict UTF-8.'
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
if ($uiSource -notmatch '\$assistantChatSurface' -or $uiSource -notmatch 'New-AssistantChatRow' -or
    $uiSource -notmatch 'assistant-agent-wave-v2\.png' -or $uiSource -notmatch 'assistant-user-custom\.png') {
    throw 'Assistant chat regression: bubble renderer or avatar assets are missing.'
}
if ($uiSource -notmatch 'Test-AssistantCleanupCommand' -or $uiSource -notmatch 'Invoke-AssistantCleanupWorkflow' -or
    $uiSource -notmatch 'Invoke-SelectedCleanupConfirmation' -or $uiSource -notmatch "RecommendationLevel -eq 'Recommended'") {
    throw 'Conversational cleanup regression: stable recommendation selection or native confirmation bridge is missing.'
}
if ($uiSource -notmatch 'Test-CDriveTravelIntent' -or $uiSource -notmatch 'Invoke-AssistantTravelQuery' -or
    $uiSource -notmatch 'TravelHost\.ps1' -or
    $uiSource -notmatch 'FLYAI.*SEARCHING' -or $uiSource -notmatch 'FLYAI_TLS' -or
    $uiSource -notmatch 'FLYAI_NETWORK' -or $uiSource -notmatch '超过 90 秒') {
    throw 'FlyAI regression: travel routing, isolation host, or consent boundary is missing.'
}
if ($uiSource -match '旅行问题将发送给飞猪 FlyAI|启用飞猪旅行建议|\$travelState\.Consent') {
    throw 'FlyAI interaction regression: travel search must not show a modal enable prompt.'
}
if ($uiSource -notmatch '输入旅行问题时，我会在后台仅将本条问题交给飞猪查询') {
    throw 'FlyAI transparency regression: non-blocking data scope disclosure is missing.'
}
if ($uiSource -notmatch 'Test-CDriveTravelQueryComplete' -or $uiSource -notmatch '\$travelState\.PendingDetails' -or
    $uiSource -notmatch 'Join-CDriveTravelQuestion' -or $uiSource -notmatch 'FLYAI_EMPTY') {
    throw 'FlyAI clarification regression: underspecified or empty-result recovery is missing.'
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

$expectedVersion = [string]((Get-Content -LiteralPath (Join-Path $scriptDir 'version.json') -Raw -Encoding UTF8 | ConvertFrom-Json).version)
if ($sideFooter.Text -ne ('版本号 v{0}' -f $expectedVersion)) {
    throw ('Version label mismatch: expected 版本号 v{0}, actual {1}' -f $expectedVersion, $sideFooter.Text)
}
if ($sideFooter.AutoSize -or $sideFooter.Left -ne $navOverview.Left -or $sideFooter.Width -ne $navOverview.Width -or
    $sideFooter.TextAlign -ne [System.Drawing.ContentAlignment]::MiddleCenter) {
    throw 'Version label spacing regression: footer must share the navigation gutter and center its text.'
}
$footerTextSize = [System.Windows.Forms.TextRenderer]::MeasureText($sideFooter.Text, $sideFooter.Font)
$footerLeftInset = [Math]::Floor(($sideFooter.ClientSize.Width - $footerTextSize.Width) / 2)
$footerRightInset = $sideFooter.ClientSize.Width - $footerTextSize.Width - $footerLeftInset
if ([Math]::Abs($footerLeftInset - $footerRightInset) -gt 1 -or $footerLeftInset -lt 8) {
    throw ('Version label has unbalanced horizontal insets: left={0}, right={1}' -f $footerLeftInset, $footerRightInset)
}
$footerBottomInset = $sideFooterHost.ClientSize.Height - $sideFooter.Bottom
if ($footerBottomInset -ne 8) {
    throw ('Version label bottom spacing regression: expected 8, actual {0}' -f $footerBottomInset)
}
if ($sideFooterHost.Dock -ne [System.Windows.Forms.DockStyle]::Bottom -or $sideFooterHost.Bottom -ne $sideBar.ClientSize.Height) {
    throw 'Version label host is not docked to the bottom of the sidebar.'
}

$utf8LogFixturePath = Join-Path $env:TEMP ('cdc-ui-utf8-log-' + [guid]::NewGuid().ToString('N') + '.log')
try {
    $utf8LogFixture = '正在扫描：微信图片与视频附件；清理完成。'
    [System.IO.File]::WriteAllText($utf8LogFixturePath, $utf8LogFixture, [System.Text.UTF8Encoding]::new($false))
    $utf8LogActual = Read-CDriveUtf8LogSnapshot $utf8LogFixturePath
    if ($utf8LogActual -ne $utf8LogFixture) {
        throw ('UTF-8 log rendering regression: expected {0}, actual {1}' -f $utf8LogFixture, $utf8LogActual)
    }
} finally {
    if (Test-Path -LiteralPath $utf8LogFixturePath) { Remove-Item -LiteralPath $utf8LogFixturePath -Force }
}

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
$initialChatRows = @($assistantChatSurface.Controls)
if ($initialChatRows.Count -lt 1 -or [string]$initialChatRows[0].Tag.Role -ne 'assistant') { throw 'Assistant greeting bubble was not created.' }
if ($null -eq $assistantAgentAvatarImage -or $null -eq $assistantUserAvatarImage) { throw 'Assistant or fixed user avatar did not load.' }
if ([System.IO.Path]::GetFileName([string]$availableUserAvatars[0]) -ne 'assistant-user-custom.png') { throw 'Uploaded custom user avatar is not the first fixed avatar source.' }
if (-not (Test-AssistantCleanupCommand '请帮我清理低风险缓存')) { throw 'Explicit conversational cleanup command was not recognized.' }
if (Test-AssistantCleanupCommand '不要清理 C盘') { throw 'Negated cleanup request was incorrectly treated as execution approval.' }
if (-not (Test-CDriveTravelIntent 'plan a weekend trip to Hangzhou')) { throw 'Travel request was not routed to the isolated provider.' }
if (Test-CDriveTravelIntent 'clean recommended cache') { throw 'Cleanup request leaked into travel routing.' }
$travelRowsBefore = @($assistantChatSurface.Controls).Count
Invoke-AssistantTravelQuery '飞猪规划一次旅行'
if ($travelState.Process -or -not $travelState.PendingDetails -or @($assistantChatSurface.Controls).Count -ne ($travelRowsBefore + 1)) {
    throw 'Underspecified travel request did not enter non-network clarification state.'
}
if ($assistantTranscript.Text -notmatch '目的地.*出发.*几天') { throw 'Travel clarification prompt is not actionable.' }
$travelState.PendingDetails = $false
$travelState.PendingQuestion = ''
if ($initialChatRows[0].Tag.Avatar.Left -ne 0 -or $initialChatRows[0].Tag.Bubble.Left -le $initialChatRows[0].Tag.Avatar.Right) { throw 'Assistant message is not left aligned.' }
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
$chatRows = @($assistantChatSurface.Controls)
$userRows = @($chatRows | Where-Object { [string]$_.Tag.Role -eq 'user' })
$assistantRows = @($chatRows | Where-Object { [string]$_.Tag.Role -eq 'assistant' })
if ($userRows.Count -lt 2 -or $assistantRows.Count -lt 3) { throw 'Two-sided assistant conversation did not render all bubbles.' }
foreach ($row in $chatRows) {
    if ($row.Tag.Bubble.Right -gt $row.ClientSize.Width -or $row.Tag.Avatar.Right -gt $row.ClientSize.Width) { throw 'Assistant bubble or avatar overflows its message row.' }
    if ($row.Tag.Label.Bottom -gt $row.Tag.Bubble.ClientSize.Height) { throw 'Assistant message text is clipped inside its bubble.' }
    if ($row.Tag.Label -isnot [System.Windows.Forms.TextBox] -or -not $row.Tag.Label.ReadOnly -or -not $row.Tag.Label.Multiline -or $row.Tag.Label.BorderStyle -ne [System.Windows.Forms.BorderStyle]::None) { throw 'Assistant message text is not a selectable read-only control.' }
    if (-not $row.Tag.Label.ShortcutsEnabled -or $row.Tag.Label.HideSelection -or $row.Tag.Label.Cursor -ne [System.Windows.Forms.Cursors]::IBeam) { throw 'Assistant message text does not expose visible standard selection and copy interaction.' }
    if ($null -eq $row.Tag.Label.ContextMenuStrip -or $row.Tag.Label.ContextMenuStrip.Items.Count -lt 2) { throw 'Assistant message copy context menu is missing.' }
    if ($row.Tag.Label.Left -ne 14 -or ($row.Tag.Bubble.ClientSize.Width - $row.Tag.Label.Right) -ne 14) { throw 'Assistant bubble horizontal text insets are inconsistent.' }
    $topInset = $row.Tag.Label.Top
    $bottomInset = $row.Tag.Bubble.ClientSize.Height - $row.Tag.Label.Bottom
    if ($topInset -lt 10 -or $bottomInset -lt 10 -or [Math]::Abs($topInset - $bottomInset) -gt 1) { throw 'Assistant message text is not vertically centered with safe insets.' }
    if ([string]$row.Tag.Role -eq 'user' -and $row.Tag.Bubble.Right -ge $row.Tag.Avatar.Left) { throw 'User message is not right aligned before its avatar.' }
}
$copyFixture = $streamRows = @($assistantRows | Where-Object { $_.Tag.Label.Text -match 'Fixture stream complete\.' })
if ($copyFixture.Count -ne 1) { throw 'Streaming response did not stay in one assistant bubble.' }
$copyFixture[0].Tag.Label.Select(0, 7)
if ([string]$copyFixture[0].Tag.Label.SelectedText -ne 'Fixture') { throw 'Assistant message text cannot be selected programmatically.' }
$copyFixture[0].Tag.Label.Select(0, 0)
$streamRows = $copyFixture
$maximumAllowedBubbleWidth = [Math]::Floor(($streamRows[0].ClientSize.Width - 50) * 0.72) + 1
if ($streamRows[0].Tag.Bubble.Width -gt $maximumAllowedBubbleWidth) { throw 'Assistant bubble exceeded the responsive maximum width.' }
$travelImagePath = Join-Path (Get-Location) 'assets\assistant-user-custom.png'
$travelResponse = [PSCustomObject]@{
    result = [PSCustomObject]@{
        data = "已按预算整理两日人文行程。`r`n`r`n## 交通`r`n- **G7509**：上海南 10:43 → 杭州东 11:53`r`n`r`n## 人文景点`r`n**[浙江省博物馆](https://router.feizhu.com/detail)**`r`n- **亮点**：了解浙江历史`r`n- **权衡**：周一闭馆`r`n`r`n## 住宿`r`n**[杭州安静酒店](https://router.feizhu.com/hotel)**`r`n- **推荐理由**：位置安静，交通方便`r`n`r`n## 预算`r`n- **合计**：约 1000 元"
        systemMessage = '*当前为体验模式*'
    }
    visualResult = [PSCustomObject]@{
        result = [PSCustomObject]@{
            data = [PSCustomObject]@{
                itemList = @([PSCustomObject]@{ info = [PSCustomObject]@{ title = '杭州实时推荐'; jumpUrl = 'https://router.feizhu.com/realtime'; picUrl = 'https://img.alicdn.com/preview.jpg' } })
            }
        }
    }
    visualMedia = @([PSCustomObject]@{ Title = '杭州实时推荐'; Link = 'https://router.feizhu.com/realtime'; LocalPath = $travelImagePath })
}
Add-AssistantTravelResult $travelResponse
[System.Windows.Forms.Application]::DoEvents()
$travelRows = @($assistantChatSurface.Controls | Where-Object { $_.Tag -and [string]$_.Tag.Type -eq 'travel' })
if ($travelRows.Count -ne 1) { throw 'Structured FlyAI travel result did not render exactly once.' }
$travelRow = $travelRows[0]
if ($travelRow.Tag.Content.Right -gt $travelRow.ClientSize.Width -or $travelRow.Tag.Content.Width -lt 260) { throw 'Structured travel result overflows its message row.' }
$travelItems = @($travelRow.Tag.Elements | Where-Object Kind -eq 'item')
if ($travelItems.Count -lt 3 -or @($travelItems | Where-Object { $_.Image.Visible }).Count -ne 1) { throw 'Travel cards or trusted visual preview are missing.' }
if (@($travelItems | Where-Object { $_.Link.Visible }).Count -lt 3) { throw 'Travel detail links are not exposed as readable actions.' }
$travelTexts = @($travelRow.Tag.Elements | Where-Object { $_.Kind -in @('text', 'notice') } | ForEach-Object Control)
if ($travelTexts.Count -lt 3 -or @($travelTexts | Where-Object { $_ -isnot [System.Windows.Forms.TextBox] -or -not $_.ReadOnly -or $null -eq $_.ContextMenuStrip }).Count -gt 0) {
    throw 'Structured travel text is not selectable and copyable.'
}
$travelTexts[0].Select(0, 2)
if ($travelTexts[0].SelectedText.Length -ne 2) { throw 'Travel summary text cannot be selected.' }
$travelOriginalSize = $form.Size
$form.Size = [System.Drawing.Size]::new(1060, 680)
[System.Windows.Forms.Application]::DoEvents()
Update-AssistantTravelRowLayout $travelRow
if ($travelRow.Tag.Content.Right -gt $travelRow.ClientSize.Width -or @($travelItems | Where-Object { $_.Panel.Right -gt $travelRow.Tag.Content.ClientSize.Width }).Count -gt 0) {
    throw 'Structured travel result overflows at the compact window size.'
}
$form.Size = $travelOriginalSize
[System.Windows.Forms.Application]::DoEvents()
$assistantChatSurface.ScrollControlIntoView($travelRow)
[System.Windows.Forms.Application]::DoEvents()
$travelPreview = [System.Drawing.Bitmap]::new($form.ClientSize.Width, $form.ClientSize.Height)
$form.DrawToBitmap($travelPreview, [System.Drawing.Rectangle]::new(0, 0, $travelPreview.Width, $travelPreview.Height))
$travelPreview.Save((Join-Path (Get-Location) 'ui-travel-preview.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$travelPreview.Dispose()
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
