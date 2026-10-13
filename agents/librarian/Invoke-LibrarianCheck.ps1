#Requires -Version 5.1
<#
.SYNOPSIS
    Read-only Librarian report on the state of this machine's agent plumbing.

.DESCRIPTION
    Reports profile file hashes, hook command paths, hook errors in recent
    transcripts, git worktrees, non-Microsoft scheduled tasks, and folder sizes.
    It never moves, deletes, prunes, or edits anything. It writes only to
    -StateDir (latest.json and previous.json) and, when given, to -OutFile.

    Exit codes: 0 no findings, 1 findings, 2 the script itself failed.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\agents\librarian\Invoke-LibrarianCheck.ps1
#>
# Deliberately a simple (not advanced) script: an unknown parameter lands in
# $args and a bad number is validated inside the try block, so both exit 2
# instead of PowerShell's own exit 1, which would read as "findings".
param(
    [string]$DevRoot = (Join-Path $HOME 'dev'),
    [string]$ProfileDir = (Join-Path $HOME '.claude'),
    $Hours = 24,
    [string]$StateDir = (Join-Path $env:LOCALAPPDATA 'LibrarianCheck'),
    [switch]$SkipSizes,
    $SizeTopN = 8,
    $SizeFileCap = 0,
    [string]$RegisterFile,
    [string]$OutFile,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Off
$script:UnboundArgs = @($args)

# ------------------------------------------------------------------ helpers

$script:Findings = New-Object 'System.Collections.Generic.List[object]'
$script:Inv = [System.Globalization.CultureInfo]::InvariantCulture
$script:GitExe = $null

function Add-Finding([string]$Section, [string]$Message, [string]$Receipt) {
    $script:Findings.Add([ordered]@{ section = $Section; message = $Message; receipt = $Receipt })
}

function Format-Time($Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [DateTimeOffset]) { return $Value.ToString('yyyy-MM-ddTHH:mm:sszzz', $script:Inv) }
    return ([datetime]$Value).ToString('yyyy-MM-ddTHH:mm:sszzz', $script:Inv)
}

function Format-Bytes($Bytes) {
    if ($null -eq $Bytes) { return 'n/a' }
    $b = [double]$Bytes
    if ($b -ge 1GB) { return [string]::Format($script:Inv, '{0:N2} GB', ($b / 1GB)) }
    if ($b -ge 1MB) { return [string]::Format($script:Inv, '{0:N1} MB', ($b / 1MB)) }
    if ($b -ge 1KB) { return [string]::Format($script:Inv, '{0:N0} KB', ($b / 1KB)) }
    return [string]::Format($script:Inv, '{0:N0} B', $b)
}

function ConvertTo-MdCell($Value) {
    if ($null -eq $Value) { return '' }
    return ((([string]$Value) -replace '\|', '\|') -replace '[\r\n]+', ' ')
}

function Show-Hash($Hash) {
    if ([string]::IsNullOrEmpty([string]$Hash)) { return 'absent' }
    return [string]$Hash
}

function Get-StringSha256([string]$Text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text))
        return (-join ($bytes | ForEach-Object { $_.ToString('x2') }))
    } finally { $sha.Dispose() }
}

function Test-PathSafe([string]$Path, [string]$Type = 'Any') {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try { return [bool](Test-Path -LiteralPath $Path -PathType $Type -ErrorAction Stop) } catch { return $false }
}

function Resolve-ParamPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

# Normalize an absolute path: forward slashes to backslashes, doubled
# backslashes (JSON or shell escaping) collapsed, trailing backslash removed.
function Get-NormalPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    $p = $Path.Trim() -replace '/', '\'
    $unc = $p.StartsWith('\\')
    $p = $p -replace '\\{2,}', '\'
    if ($unc) { $p = '\' + $p }
    if ($p.Length -gt 3) { $p = $p.TrimEnd('\') }
    try { $p = [System.IO.Path]::GetFullPath($p) } catch { }
    return $p
}

function Test-UnderPath([string]$Path, [string]$Root) {
    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Root)) { return $false }
    $r = $Root.TrimEnd('\') + '\'
    return ($Path.TrimEnd('\') + '\').StartsWith($r, [StringComparison]::OrdinalIgnoreCase)
}

function Test-SkipByName([string]$Name) {
    return ([string]$Name).StartsWith('_Quarantine_', [StringComparison]::OrdinalIgnoreCase)
}

function Test-PathHasQuarantine([string]$Path) {
    foreach ($seg in ([string]$Path -split '[\\/]')) { if (Test-SkipByName $seg) { return $true } }
    return $false
}

function Test-Frozen([string]$Folder) {
    return (Test-PathSafe (Join-Path $Folder 'FROZEN-DEPLOYMENT.md') 'Leaf')
}

function Resolve-EnvName([string]$Name, [string]$Fallback) {
    if ($Name -eq 'HOME') { return $HOME }
    $v = [Environment]::GetEnvironmentVariable($Name)
    if ($v) { return $v }
    return $Fallback
}

# Expand ~, $HOME, ${NAME}, $env:NAME, %NAME% and Git Bash /c/... forms.
function Expand-PathToken([string]$Text) {
    if ($null -eq $Text) { return $null }
    $t = $Text
    if ($t -match '^~(?=$|[\\/])') { $t = $HOME + $t.Substring(1) }
    $t = [regex]::Replace($t, '\$env:([A-Za-z_][A-Za-z0-9_]*)', [System.Text.RegularExpressions.MatchEvaluator]{
            param($m) Resolve-EnvName $m.Groups[1].Value $m.Value })
    $t = [regex]::Replace($t, '\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)', [System.Text.RegularExpressions.MatchEvaluator]{
            param($m)
            $n = $m.Groups[1].Value
            if (-not $n) { $n = $m.Groups[2].Value }
            Resolve-EnvName $n $m.Value })
    $t = [Environment]::ExpandEnvironmentVariables($t)
    if ($t -match '^/([A-Za-z])/(.*)$') { $t = $Matches[1].ToUpperInvariant() + ':\' + $Matches[2] }
    return $t
}

function ConvertTo-AbsolutePath([string]$Token) {
    if ([string]::IsNullOrWhiteSpace($Token)) { return $null }
    $t = Expand-PathToken $Token.Trim()
    $t = $t.Trim().Trim([char[]]@([char]34, [char]39))
    if ($t -match '^[A-Za-z]:[\\/]' -or $t -match '^\\\\[^\\]') { return (Get-NormalPath $t) }
    return $null
}

# Shell-like split: single quotes are literal, double quotes honour \" and \\,
# adjacent quoted parts join one token. Also returns each quoted segment.
function Split-CommandLine([string]$Text) {
    $tokens = New-Object 'System.Collections.Generic.List[string]'
    $inner = New-Object 'System.Collections.Generic.List[string]'
    $sb = New-Object System.Text.StringBuilder
    $inToken = $false
    $i = 0
    $n = $Text.Length
    while ($i -lt $n) {
        $c = $Text[$i]
        if ($c -eq [char]39) {
            $j = $Text.IndexOf([char]39, $i + 1)
            if ($j -lt 0) { $j = $n }
            $seg = $Text.Substring($i + 1, $j - $i - 1)
            [void]$sb.Append($seg)
            $inner.Add($seg)
            $inToken = $true
            $i = $j + 1
            continue
        }
        if ($c -eq [char]34) {
            $seg = New-Object System.Text.StringBuilder
            $i++
            while ($i -lt $n -and $Text[$i] -ne [char]34) {
                if ($Text[$i] -eq [char]92 -and ($i + 1) -lt $n -and ($Text[$i + 1] -eq [char]34 -or $Text[$i + 1] -eq [char]92)) {
                    [void]$seg.Append($Text[$i + 1])
                    $i += 2
                    continue
                }
                [void]$seg.Append($Text[$i])
                $i++
            }
            $i++
            $s = $seg.ToString()
            [void]$sb.Append($s)
            $inner.Add($s)
            $inToken = $true
            continue
        }
        if ([char]::IsWhiteSpace($c)) {
            if ($inToken) { $tokens.Add($sb.ToString()); [void]$sb.Clear(); $inToken = $false }
            $i++
            continue
        }
        [void]$sb.Append($c)
        $inToken = $true
        $i++
    }
    if ($inToken) { $tokens.Add($sb.ToString()) }
    return [pscustomobject]@{ Tokens = $tokens.ToArray(); Inner = $inner.ToArray() }
}

# Token lists for the command and for every quoted segment that is itself a
# command (for example powershell -Command "& 'C:\x\y.ps1'").
function Get-TokenSequences([string]$Text, [int]$Depth) {
    $seqs = New-Object 'System.Collections.Generic.List[object]'
    $split = Split-CommandLine $Text
    $seqs.Add($split.Tokens)
    if ($Depth -lt 3) {
        foreach ($seg in $split.Inner) {
            if ($seg -match '\s') {
                foreach ($s in (Get-TokenSequences $seg ($Depth + 1))) { $seqs.Add($s) }
            }
        }
    }
    return , $seqs
}

# Absolute script paths (by extension) and folder options (--*-dir, git -C).
function Get-PathRefs([string]$Command, [string[]]$Extensions) {
    $refs = New-Object 'System.Collections.Generic.List[object]'
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $extRx = '(?i)\.(' + (($Extensions | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')$'
    foreach ($seq in (Get-TokenSequences $Command 0)) {
        for ($k = 0; $k -lt $seq.Count; $k++) {
            $tok = [string]$seq[$k]
            $opt = $null
            $val = $null
            if ($tok -match '^(--?[A-Za-z][A-Za-z0-9-]*-dir)=(.+)$') { $opt = $Matches[1]; $val = $Matches[2] }
            elseif ((($tok -match '^--?[A-Za-z][A-Za-z0-9-]*-dir$') -or ($tok -ceq '-C')) -and ($k + 1) -lt $seq.Count) { $opt = $tok; $val = [string]$seq[$k + 1] }
            if ($opt) {
                $p = ConvertTo-AbsolutePath $val
                if ($p -and $seen.Add('folder|' + $p)) { $refs.Add([pscustomobject]@{ Kind = 'folder'; Path = $p; Option = $opt }) }
            }
            $cand = $tok
            if ($tok -match '^-{1,2}[^=\s]+=(.+)$') { $cand = $Matches[1] }
            $cand = $cand.TrimEnd([char[]]@(';', ',', ')', '&', '|'))
            if ($cand -match $extRx) {
                $p = ConvertTo-AbsolutePath $cand
                if ($p -and $seen.Add('script|' + $p)) { $refs.Add([pscustomobject]@{ Kind = 'script'; Path = $p; Option = $null }) }
            }
        }
    }
    return , $refs
}

function Resolve-Executable([string]$Name) {
    $n = Expand-PathToken ([string]$Name)
    if ($null -ne $n) { $n = $n.Trim().Trim([char[]]@([char]34, [char]39)) }
    if ([string]::IsNullOrWhiteSpace($n)) { return $null }
    if ($n -match '^[A-Za-z]:[\\/]' -or $n.StartsWith('\\')) {
        $full = Get-NormalPath $n
        return [pscustomobject]@{ Path = $full; Exists = (Test-PathSafe $full 'Leaf'); How = 'absolute' }
    }
    $exts = @('')
    $hasExt = $false
    try { $hasExt = [System.IO.Path]::HasExtension($n) } catch { }
    if (-not $hasExt) { $exts = @('') + @(([string]$env:PATHEXT -split ';') | Where-Object { $_ }) }
    $dirs = New-Object 'System.Collections.Generic.List[string]'
    if ($env:SystemRoot) { $dirs.Add((Join-Path $env:SystemRoot 'System32')); $dirs.Add($env:SystemRoot) }
    foreach ($d in ([string]$env:PATH -split ';')) {
        $d2 = [Environment]::ExpandEnvironmentVariables($d.Trim().Trim([char]34))
        if ($d2) { $dirs.Add($d2) }
    }
    foreach ($d in $dirs) {
        foreach ($x in $exts) {
            $c = $null
            try { $c = [System.IO.Path]::Combine($d, $n + $x) } catch { continue }
            if (Test-PathSafe $c 'Leaf') { return [pscustomobject]@{ Path = $c; Exists = $true; How = 'search path' } }
        }
    }
    return [pscustomobject]@{ Path = $n; Exists = $false; How = 'search path' }
}

function ConvertTo-ProcessArg([string]$Arg) {
    if ($Arg -eq '' -or $Arg -match '[\s"]') { return '"' + ($Arg -replace '"', '\"') + '"' }
    return $Arg
}

# Runs one read-only git command. Every call goes through here, always with
# -C <path> --no-optional-locks, and only with the subcommands the caller passes
# (worktree list --porcelain, status --porcelain, log -1 --format=%cI).
function Invoke-GitRead([string]$Path, [string[]]$GitArgs) {
    $all = @('-C', $Path.TrimEnd('\'), '--no-optional-locks') + $GitArgs
    $argLine = ($all | ForEach-Object { ConvertTo-ProcessArg $_ }) -join ' '
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $script:GitExe
    $psi.Arguments = $argLine
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $psi.EnvironmentVariables['GIT_OPTIONAL_LOCKS'] = '0'
    $psi.EnvironmentVariables['GIT_TERMINAL_PROMPT'] = '0'
    $p = [System.Diagnostics.Process]::Start($psi)
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit(120000)) {
        try { $p.Kill() } catch { }
        return [pscustomobject]@{ ExitCode = -1; Out = ''; Err = 'timed out after 120 s'; Command = ('git ' + $argLine) }
    }
    $p.WaitForExit()
    return [pscustomobject]@{ ExitCode = $p.ExitCode; Out = $outTask.Result; Err = $errTask.Result; Command = ('git ' + $argLine) }
}

function Get-FirstLine([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $l = (($Text -split "`n") | Where-Object { $_.Trim() } | Select-Object -First 1)
    $l = ([string]$l).Trim()
    if ($l.Length -gt 200) { $l = $l.Substring(0, 200) }
    return $l
}

function Test-InHomeDotFolder([string]$Path) {
    if (-not (Test-UnderPath $Path $HOME)) { return $false }
    $h = $HOME.TrimEnd('\')
    if ($Path.Length -le $h.Length + 1) { return $false }
    $rel = $Path.Substring($h.Length + 1)
    $first = ($rel -split '\\')[0]
    return $first.StartsWith('.')
}

function Test-WorktreeNestName([string]$Name) {
    return (@('.worktrees', 'worktrees', '_wt') -contains $Name) -or $Name.EndsWith('-worktrees', [StringComparison]::OrdinalIgnoreCase)
}

function Get-FolderClass([string]$Path, [string]$Name) {
    if ((Test-UnderPath $Path $env:APPDATA) -or (Test-UnderPath $Path $env:LOCALAPPDATA) -or (Test-InHomeDotFolder $Path)) { return 'app-managed' }
    if (Test-PathSafe (Join-Path $Path '.git')) { return 'repo' }
    if (Test-WorktreeNestName $Name) { return 'worktree-nest' }
    if (@('runs', 'evidence', 'Archive', '_archive') -contains $Name) { return 'evidence' }
    if ($Name.StartsWith('_') -or $Name.StartsWith('scratch', [StringComparison]::OrdinalIgnoreCase) -or $Name.StartsWith('tmp', [StringComparison]::OrdinalIgnoreCase)) { return 'scratch' }
    return 'unclassified'
}

# Sum of file lengths under a folder. Manual walk so one unreadable folder does
# not stop the count; reparse points (junctions, links, cloud placeholders) are
# not followed.
function Measure-Folder([string]$Path, [int]$Cap) {
    $bytes = [int64]0
    $files = [int64]0
    $errors = 0
    $links = 0
    $capHit = $false
    $rp = [System.IO.FileAttributes]::ReparsePoint
    $stack = New-Object 'System.Collections.Generic.Stack[System.IO.DirectoryInfo]'
    $stack.Push((New-Object System.IO.DirectoryInfo $Path))
    while ($stack.Count -gt 0 -and -not $capHit) {
        $d = $stack.Pop()
        try {
            foreach ($e in $d.EnumerateFileSystemInfos()) {
                if ($e -is [System.IO.DirectoryInfo]) {
                    if (($e.Attributes -band $rp) -ne 0) { $links++; continue }
                    if ($e.Name.StartsWith('_Quarantine_', [StringComparison]::OrdinalIgnoreCase)) { continue }
                    $stack.Push($e)
                } else {
                    $bytes += $e.Length
                    $files++
                    if ($Cap -gt 0 -and $files -ge $Cap) { $capHit = $true; break }
                }
            }
        } catch { $errors++ }
    }
    return [pscustomobject]@{ Bytes = $bytes; Files = $files; Errors = $errors; LinksSkipped = $links; CapHit = $capHit }
}

# Registers kept in public places often redact account SIDs in task names
# (S-1-5-21-<redacted>-1001). Names are compared with any SID, real or
# redacted, folded to one placeholder.
function Get-TaskNameKey([string]$Name) {
    return ([string]$Name -replace 'S-1-5-21-(?:\d+|<[^>]*>)(?:-(?:\d+|<[^>]*>))*', '<SID>')
}

function Read-JsonFile([string]$Path) {
    return ((Get-Content -Raw -LiteralPath $Path -Encoding UTF8) | ConvertFrom-Json)
}

# ------------------------------------------------------------------ main

try {
    if ($script:UnboundArgs.Count -gt 0) { throw ('Unknown argument(s): ' + ($script:UnboundArgs -join ' ')) }
    $h = 0; $topN = 0; $cap = 0
    if (-not [int]::TryParse([string]$Hours, [ref]$h) -or $h -lt 1) { throw '-Hours must be a whole number of 1 or more.' }
    if (-not [int]::TryParse([string]$SizeTopN, [ref]$topN) -or $topN -lt 1) { throw '-SizeTopN must be a whole number of 1 or more.' }
    if (-not [int]::TryParse([string]$SizeFileCap, [ref]$cap) -or $cap -lt 0) { throw '-SizeFileCap must be a whole number of 0 or more.' }
    $Hours = $h; $SizeTopN = $topN; $SizeFileCap = $cap

    $DevRoot = Get-NormalPath (Resolve-ParamPath $DevRoot)
    $ProfileDir = Get-NormalPath (Resolve-ParamPath $ProfileDir)
    $StateDir = Get-NormalPath (Resolve-ParamPath $StateDir)
    if ($RegisterFile) {
        $RegisterFile = Resolve-ParamPath $RegisterFile
        if (-not (Test-PathSafe $RegisterFile 'Leaf')) { throw ('-RegisterFile not found: ' + $RegisterFile) }
    }
    if ($OutFile) { $OutFile = Resolve-ParamPath $OutFile }
    $HomeDir = Get-NormalPath $HOME

    $started = Get-Date
    $timings = [ordered]@{}
    $notes = New-Object 'System.Collections.Generic.List[string]'

    # Previous run: latest.json in the state folder becomes the baseline.
    $latestPath = Join-Path $StateDir 'latest.json'
    $previousPath = Join-Path $StateDir 'previous.json'
    $prev = $null
    if (Test-PathSafe $latestPath 'Leaf') {
        try { $prev = Read-JsonFile $latestPath } catch { $notes.Add('latest.json in the state folder did not parse; no comparison with the previous run.') }
    }

    # -------------------------------------------------- 1. Profile files
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $prevHash = @{}
    if ($prev -and $prev.profile -and $prev.profile.files) {
        foreach ($pf in @($prev.profile.files)) { if ($pf -and $pf.path) { $prevHash[[string]$pf.path] = $pf } }
    }
    $profileRows = New-Object 'System.Collections.Generic.List[object]'
    foreach ($name in @('settings.json', 'settings.local.json', 'CLAUDE.md', 'kernel.md')) {
        $path = Join-Path $ProfileDir $name
        $exists = Test-PathSafe $path 'Leaf'
        $hash = $null
        if ($exists) { $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
        $prevSha = $null
        $changed = $null
        if ($prevHash.ContainsKey($path)) {
            $prevSha = $prevHash[$path].sha256
            $changed = ([string]$prevSha -ne [string]$hash)
            if ($changed) {
                Add-Finding 'profile' ('Profile file changed between runs: ' + $path) ('sha256 ' + (Show-Hash $prevSha) + ' -> ' + (Show-Hash $hash))
            }
        }
        $profileRows.Add([ordered]@{ name = $name; path = $path; exists = $exists; sha256 = $hash; previousSha256 = $prevSha; changed = $changed })
    }
    $timings['profile'] = [math]::Round($sw.Elapsed.TotalSeconds, 2)

    # -------------------------------------------------- 2. Hooks
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $hookExts = @('mjs', 'js', 'ps1', 'py', 'sh', 'cmd', 'bat', 'exe')
    $hookEvents = New-Object 'System.Collections.Generic.List[object]'
    $hookGroups = [ordered]@{}
    $hookCommands = New-Object 'System.Collections.Generic.List[object]'
    $settingsRead = New-Object 'System.Collections.Generic.List[string]'
    foreach ($sf in @('settings.json', 'settings.local.json')) {
        $sp = Join-Path $ProfileDir $sf
        if (-not (Test-PathSafe $sp 'Leaf')) { continue }
        $obj = $null
        try { $obj = Read-JsonFile $sp } catch {
            Add-Finding 'hooks' ('Settings file does not parse as JSON: ' + $sp) 'ConvertFrom-Json failed'
            continue
        }
        $settingsRead.Add($sp)
        if ($null -eq $obj -or $null -eq $obj.hooks) { continue }
        foreach ($ev in $obj.hooks.PSObject.Properties) {
            $blocks = @($ev.Value | Where-Object { $null -ne $_ })
            $cmdCount = 0
            foreach ($b in $blocks) {
                foreach ($hk in @($b.hooks | Where-Object { $null -ne $_ })) {
                    $cmd = [string]$hk.command
                    if ([string]::IsNullOrWhiteSpace($cmd)) { continue }
                    $cmdCount++
                    $refs = Get-PathRefs $cmd $hookExts
                    $hookCommands.Add([ordered]@{ source = $sp; event = $ev.Name; commandSha256 = (Get-StringSha256 $cmd); paths = $refs.Count })
                    foreach ($ref in $refs) {
                        $key = $sp + '|' + $ref.Kind + '|' + $ref.Path.ToLowerInvariant()
                        if (-not $hookGroups.Contains($key)) {
                            $hookGroups[$key] = [ordered]@{
                                source = $sp; kind = $ref.Kind; option = $ref.Option; path = $ref.Path
                                exists = (Test-PathSafe $ref.Path)
                                events = (New-Object 'System.Collections.Generic.List[string]')
                            }
                        }
                        if (-not $hookGroups[$key].events.Contains($ev.Name)) { $hookGroups[$key].events.Add($ev.Name) }
                    }
                }
            }
            $hookEvents.Add([ordered]@{ source = $sp; event = $ev.Name; blocks = $blocks.Count; commands = $cmdCount })
        }
    }
    $hookPaths = New-Object 'System.Collections.Generic.List[object]'
    foreach ($g in $hookGroups.Values) {
        $hookPaths.Add($g)
        if (-not $g.exists) {
            $what = 'script'
            if ($g.kind -eq 'folder') { $what = 'folder (' + $g.option + ')' }
            Add-Finding 'hooks' ('Hook ' + $what + ' missing for ' + ($g.events -join ', ') + ': ' + $g.path) ("Test-Path -LiteralPath '" + $g.path + "' = False")
        }
    }
    $timings['hooks'] = [math]::Round($sw.Elapsed.TotalSeconds, 2)

    # -------------------------------------------------- 3. Hook errors in recent transcripts
    # A real hook error is an attachment record whose JSON holds the unescaped
    # pair "type":"hook_non_blocking_error". The same words inside a message or
    # tool input are JSON-escaped, so conversation text about hooks is counted
    # separately as a mention and never as an error. MODULE_NOT_FOUND counts
    # only on a line that is a hook record (it has an unescaped "hookEvent" key).
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $projRoot = Join-Path $ProfileDir 'projects'
    $cut = (Get-Date).AddHours(-$Hours)
    $rxHookType = New-Object System.Text.RegularExpressions.Regex '"type"\s*:\s*"hook_non_blocking_error"'
    $rxHookEvent = New-Object System.Text.RegularExpressions.Regex '"hookEvent"\s*:'
    $transcriptRows = New-Object 'System.Collections.Generic.List[object]'
    $scanned = 0
    $mentionTotal = 0
    $unreadable = 0
    $projExists = Test-PathSafe $projRoot 'Container'
    if ($projExists) {
        $files = @(Get-ChildItem -LiteralPath $projRoot -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
                Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Force -Filter '*.jsonl' -ErrorAction SilentlyContinue
            } | Where-Object { $_.LastWriteTime -ge $cut })
        foreach ($f in $files) {
            $scanned++
            $hookLines = 0; $modLines = 0; $errLines = 0; $mentions = 0
            $sr = $null
            try {
                $fs = [System.IO.FileStream]::new($f.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
                $sr = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8)
                while ($null -ne ($line = $sr.ReadLine())) {
                    $hasHook = $line.IndexOf('hook_non_blocking_error', [StringComparison]::Ordinal) -ge 0
                    $hasMod = $line.IndexOf('MODULE_NOT_FOUND', [StringComparison]::Ordinal) -ge 0
                    if (-not ($hasHook -or $hasMod)) { continue }
                    $isHook = $hasHook -and $rxHookType.IsMatch($line)
                    $isMod = $hasMod -and $rxHookEvent.IsMatch($line)
                    if ($isHook) { $hookLines++ }
                    if ($isMod) { $modLines++ }
                    if ($isHook -or $isMod) { $errLines++ } else { $mentions++ }
                }
            } catch { $unreadable++ } finally { if ($sr) { $sr.Dispose() } }
            $mentionTotal += $mentions
            if ($errLines -gt 0) {
                $transcriptRows.Add([ordered]@{ path = $f.FullName; modified = (Format-Time $f.LastWriteTime); hookErrorLines = $hookLines; moduleNotFoundLines = $modLines; lines = $errLines })
                Add-Finding 'transcripts' ('Hook errors in transcript: ' + $f.FullName) ('lines: ' + $errLines + ' (hook_non_blocking_error ' + $hookLines + ', MODULE_NOT_FOUND ' + $modLines + ')')
            }
        }
    }
    $timings['transcripts'] = [math]::Round($sw.Elapsed.TotalSeconds, 2)

    # -------------------------------------------------- 4. Worktrees
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $git = Resolve-Executable 'git'
    if ($git -and $git.Exists) { $script:GitExe = $git.Path }
    $repoRows = New-Object 'System.Collections.Generic.List[object]'
    $worktreeRows = New-Object 'System.Collections.Generic.List[object]'
    $skippedRows = New-Object 'System.Collections.Generic.List[object]'
    $unregisteredRows = New-Object 'System.Collections.Generic.List[object]'
    $retiredRows = New-Object 'System.Collections.Generic.List[object]'
    $seenWorktrees = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $devExists = Test-PathSafe $DevRoot 'Container'
    $codexNest = Join-Path $HomeDir '.codex\worktrees'
    $wtNest = Join-Path $DevRoot '_wt'
    if (-not $devExists) {
        $notes.Add('DevRoot not found: ' + $DevRoot)
    } elseif (-not $script:GitExe) {
        Add-Finding 'worktrees' 'git not found on PATH; the worktree section did not run' 'Resolve git through PATH and PATHEXT: not found'
    } else {
        foreach ($dir in @(Get-ChildItem -LiteralPath $DevRoot -Directory -Force -ErrorAction SilentlyContinue | Sort-Object Name)) {
            if (Test-SkipByName $dir.Name) { $skippedRows.Add([ordered]@{ path = $dir.FullName; rule = '_Quarantine_ prefix' }); continue }
            if (-not (Test-PathSafe (Join-Path $dir.FullName '.git'))) { continue }
            if (Test-Frozen $dir.FullName) { $skippedRows.Add([ordered]@{ path = $dir.FullName; rule = 'FROZEN-DEPLOYMENT.md' }); continue }
            $repo = $dir.FullName
            $r = Invoke-GitRead $repo @('worktree', 'list', '--porcelain')
            if ($r.ExitCode -ne 0) {
                $repoRows.Add([ordered]@{ path = $repo; ok = $false; worktrees = 0; error = (Get-FirstLine $r.Err) })
                Add-Finding 'worktrees' ('git worktree list failed for ' + $repo + ': ' + (Get-FirstLine $r.Err)) ($r.Command + ' -> exit ' + $r.ExitCode)
                continue
            }
            $entries = New-Object 'System.Collections.Generic.List[object]'
            foreach ($blk in ((($r.Out -replace "`r", '') -split "`n`n") | Where-Object { $_.Trim() })) {
                $e = [ordered]@{ path = $null; head = $null; branch = $null; detached = $false; bare = $false; locked = $false; prunable = $false }
                foreach ($l in ($blk -split "`n")) {
                    if ($l.StartsWith('worktree ')) { $e.path = Get-NormalPath $l.Substring(9) }
                    elseif ($l.StartsWith('HEAD ')) { $e.head = $l.Substring(5).Trim() }
                    elseif ($l.StartsWith('branch ')) { $e.branch = ($l.Substring(7).Trim() -replace '^refs/heads/', '') }
                    elseif ($l -eq 'detached') { $e.detached = $true }
                    elseif ($l -eq 'bare') { $e.bare = $true }
                    elseif ($l.StartsWith('locked')) { $e.locked = $true }
                    elseif ($l.StartsWith('prunable')) { $e.prunable = $true }
                }
                if ($e.path) { $entries.Add($e) }
            }
            $registered = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
            foreach ($e in $entries) { [void]$registered.Add($e.path) }
            $repoRows.Add([ordered]@{ path = $repo; ok = $true; worktrees = [math]::Max(0, $entries.Count - 1); error = $null })
            $nests = @((Join-Path $repo '.claude\worktrees'), (Join-Path $repo '.worktrees'), $codexNest, $wtNest)
            for ($w = 1; $w -lt $entries.Count; $w++) {
                $e = $entries[$w]
                if (-not $seenWorktrees.Add($e.path)) { continue }
                $exists = Test-PathSafe $e.path 'Container'
                if ((Test-PathHasQuarantine $e.path) -or ($exists -and (Test-Frozen $e.path))) {
                    $skippedRows.Add([ordered]@{ path = $e.path; rule = 'worktree skipped by rule' })
                    continue
                }
                $last = $null; $ageDays = $null
                if ($e.head) {
                    $lr = Invoke-GitRead $repo @('log', '-1', '--format=%cI', $e.head)
                    if ($lr.ExitCode -eq 0 -and $lr.Out.Trim()) {
                        try {
                            $dto = [DateTimeOffset]::Parse($lr.Out.Trim(), $script:Inv)
                            $last = Format-Time $dto
                            $ageDays = [math]::Round(((Get-Date) - $dto.LocalDateTime).TotalDays, 1)
                        } catch { }
                    }
                }
                $dirty = $null
                if ($exists) {
                    $st2 = Invoke-GitRead $e.path @('status', '--porcelain')
                    if ($st2.ExitCode -eq 0) { $dirty = @(($st2.Out -split "`n") | Where-Object { $_.Trim() }).Count }
                }
                $nest = $null
                foreach ($nd in $nests) { if (Test-UnderPath $e.path $nd) { $nest = $nd; break } }
                $branch = $e.branch
                if ($e.detached -or -not $branch) { $branch = 'detached' }
                $status = New-Object 'System.Collections.Generic.List[string]'
                if (-not $exists) {
                    $status.Add('missing')
                    Add-Finding 'worktrees' ('Worktree path missing on disk: ' + $e.path) ('git -C ' + $repo + ' --no-optional-locks worktree list --porcelain; Test-Path = False')
                }
                if (-not $nest) {
                    $status.Add('outside nests')
                    Add-Finding 'worktrees' ('Worktree outside every allowed nest: ' + $e.path) ('git -C ' + $repo + ' --no-optional-locks worktree list --porcelain')
                }
                if ($exists -and $branch -eq 'detached' -and $null -ne $ageDays -and $ageDays -gt 7 -and $dirty -eq 0) {
                    $status.Add('idle detached')
                    Add-Finding 'worktrees' ('Detached worktree idle ' + $ageDays + ' days with 0 dirty files, eligible for a manifest row: ' + $e.path) ('last commit ' + $last + '; git status --porcelain: 0 lines')
                }
                $worktreeRows.Add([ordered]@{
                        repo = $repo; path = $e.path; branch = $branch; head = $e.head; lastCommit = $last; ageDays = $ageDays
                        dirty = $dirty; exists = $exists; nest = $nest; locked = $e.locked; prunable = $e.prunable; status = $status.ToArray()
                    })
            }
            foreach ($nestDir in @((Join-Path $repo '.claude\worktrees'), (Join-Path $repo '.worktrees'))) {
                if (-not (Test-PathSafe $nestDir 'Container')) { continue }
                foreach ($c in @(Get-ChildItem -LiteralPath $nestDir -Directory -Force -ErrorAction SilentlyContinue)) {
                    if (Test-SkipByName $c.Name) { $skippedRows.Add([ordered]@{ path = $c.FullName; rule = '_Quarantine_ prefix' }); continue }
                    $cp = Get-NormalPath $c.FullName
                    if (-not $registered.Contains($cp)) {
                        $unregisteredRows.Add([ordered]@{ repo = $repo; path = $cp })
                        Add-Finding 'worktrees' ('Folder in a worktree nest is not a registered worktree: ' + $cp) ('not listed by git -C ' + $repo + ' --no-optional-locks worktree list --porcelain')
                    }
                }
            }
        }
    }
    if ($devExists) {
        $retired = @()
        $plain = Join-Path $DevRoot 'worktrees'
        if (Test-PathSafe $plain 'Container') { $retired += $plain }
        $retired += @(Get-ChildItem -LiteralPath $DevRoot -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*-worktrees' } | ForEach-Object { $_.FullName })
        foreach ($rn in $retired) {
            $cnt = @(Get-ChildItem -LiteralPath $rn -Force -ErrorAction SilentlyContinue).Count
            $retiredRows.Add([ordered]@{ path = $rn; entries = $cnt })
            if ($cnt -gt 0) { Add-Finding 'worktrees' ('Retired worktree nest is not empty: ' + $rn) ('Get-ChildItem -Force: ' + $cnt + ' entries') }
        }
    }
    $timings['worktrees'] = [math]::Round($sw.Elapsed.TotalSeconds, 2)

    # -------------------------------------------------- 5. Scheduled tasks
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $taskExts = @('ps1', 'py', 'pyw', 'vbs', 'exe', 'js', 'mjs', 'cmd', 'bat', 'sh')
    $okResults = @([int64]0, [int64]0x41301, [int64]0x41303)
    $regNames = $null
    if ($RegisterFile) {
        $regNames = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        foreach ($line in (Get-Content -LiteralPath $RegisterFile -Encoding UTF8)) {
            if ($line -match '^\s*\|\s*`([^`]+)`') {
                $rn = $Matches[1].Trim()
                [void]$regNames.Add($rn)
                [void]$regNames.Add((Get-TaskNameKey $rn))
            }
        }
    }
    $taskRows = New-Object 'System.Collections.Generic.List[object]'
    $allTasks = @()
    $tasksOk = $true
    try { $allTasks = @(Get-ScheduledTask -ErrorAction Stop) } catch {
        $tasksOk = $false
        Add-Finding 'tasks' 'Could not list scheduled tasks; the section did not run' ('Get-ScheduledTask: ' + $_.Exception.Message)
    }
    foreach ($t in ($allTasks | Sort-Object TaskPath, TaskName)) {
        if ([string]$t.TaskPath -like '\Microsoft\*') { continue }
        $full = [string]$t.TaskPath + [string]$t.TaskName
        $state = [string]$t.State
        $enabled = ($state -ne 'Disabled')
        $info = $null
        try { $info = $t | Get-ScheduledTaskInfo -ErrorAction Stop } catch { }
        $lastResult = $null; $lastRun = $null
        if ($info) {
            $lastResult = [int64]$info.LastTaskResult
            if ($info.LastRunTime -and ([datetime]$info.LastRunTime).Year -ge 2000) { $lastRun = Format-Time $info.LastRunTime }
        }
        $hex = $null
        if ($null -ne $lastResult) { $hex = '0x{0:X}' -f $lastResult }
        $act = @($t.Actions) | Select-Object -First 1
        $exe = $null
        $actionKind = 'none'
        $paths = New-Object 'System.Collections.Generic.List[object]'
        if ($act -and $act.Execute) {
            $actionKind = 'exec'
            $exe = Resolve-Executable ([string]$act.Execute)
            $argText = [string]$act.Arguments
            $wd = [string]$act.WorkingDirectory
            if ($argText) {
                $seenTask = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
                foreach ($ref in (Get-PathRefs $argText $taskExts)) {
                    if ($seenTask.Add($ref.Path)) { $paths.Add([ordered]@{ path = $ref.Path; exists = (Test-PathSafe $ref.Path) }) }
                }
                foreach ($seq in (Get-TokenSequences $argText 0)) {
                    for ($k = 0; $k -lt ($seq.Count - 1); $k++) {
                        if ($seq[$k] -match '^-(?i:file)$') {
                            $v = [string]$seq[$k + 1]
                            if (-not (ConvertTo-AbsolutePath $v) -and $wd) {
                                $base = Expand-PathToken $wd.Trim([char]34)
                                $rel = $null
                                try { $rel = Get-NormalPath ([System.IO.Path]::Combine($base, $v)) } catch { }
                                if ($rel -and $seenTask.Add($rel)) { $paths.Add([ordered]@{ path = $rel; exists = (Test-PathSafe $rel) }) }
                            }
                        }
                    }
                }
            }
        } elseif ($act) { $actionKind = 'com-handler' }
        $inRegister = $null
        if ($regNames) {
            $inRegister = ($regNames.Contains($full) -or $regNames.Contains((Get-TaskNameKey $full)) -or
                $regNames.Contains([string]$t.TaskName) -or $regNames.Contains((Get-TaskNameKey ([string]$t.TaskName))))
        }
        $exePath = $null; $exeExists = $null
        if ($exe) { $exePath = $exe.Path; $exeExists = $exe.Exists }
        $taskRows.Add([ordered]@{
                name = $full; state = $state; enabled = $enabled; lastRun = $lastRun; lastResult = $lastResult; lastResultHex = $hex
                actionKind = $actionKind; execute = $exePath; executeExists = $exeExists; paths = $paths.ToArray(); inRegister = $inRegister
            })
        if ($enabled -and $null -ne $lastResult -and -not ($okResults -contains $lastResult)) {
            $when = 'never'
            if ($lastRun) { $when = $lastRun }
            Add-Finding 'tasks' ('Scheduled task last result ' + $hex + ': ' + $full) ('Get-ScheduledTaskInfo LastTaskResult ' + $hex + ', LastRunTime ' + $when)
        }
        if ($exe -and -not $exe.Exists) {
            Add-Finding 'tasks' ('Scheduled task executable not found: ' + $full + ' -> ' + $exe.Path) ('Test-Path (' + $exe.How + ') = False')
        }
        foreach ($pp in $paths) {
            if (-not $pp.exists) { Add-Finding 'tasks' ('Scheduled task action path missing: ' + $full + ' -> ' + $pp.path) ("Test-Path -LiteralPath '" + $pp.path + "' = False") }
        }
        if ($regNames -and -not $inRegister) {
            Add-Finding 'tasks' ('Scheduled task not in register: ' + $full) ('no backtick-quoted first cell matches in ' + $RegisterFile)
        }
    }
    $timings['tasks'] = [math]::Round($sw.Elapsed.TotalSeconds, 2)

    # -------------------------------------------------- 6. Folder layout and sizes
    # The layout check is cheap and always runs; -SkipSizes skips only the
    # size measurement.
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $layoutRows = New-Object 'System.Collections.Generic.List[object]'
    if ($devExists) {
        foreach ($c in @(Get-ChildItem -LiteralPath $DevRoot -Force -ErrorAction SilentlyContinue | Sort-Object Name)) {
            if (Test-SkipByName $c.Name) { continue }
            $isDir = $c.PSIsContainer
            $kind = 'other'
            if ($isDir -and (Test-PathSafe (Join-Path $c.FullName '.git'))) { $kind = 'repo' }
            elseif ($isDir -and (Test-WorktreeNestName $c.Name)) { $kind = 'worktree-nest' }
            elseif ($isDir -and (@('Archive', 'Tools') -contains $c.Name)) { $kind = $c.Name }
            elseif (-not $isDir) { $kind = 'file' }
            $allowed = ($kind -ne 'other' -and $kind -ne 'file')
            $layoutRows.Add([ordered]@{ path = $c.FullName; kind = $kind; allowed = $allowed })
            if (-not $allowed) {
                Add-Finding 'layout' ('DevRoot child outside the filing standard: ' + $c.FullName) ('kind ' + $kind + '; allowed: repo, worktree nest, Archive, Tools, _wt')
            }
        }
    }
    $sizeRoots = New-Object 'System.Collections.Generic.List[object]'
    $sizeChildren = New-Object 'System.Collections.Generic.List[object]'
    $prevSizes = @{}
    $prevHadSizes = $false
    if ($prev -and $prev.sizes -and $prev.sizes.children) {
        foreach ($pc in @($prev.sizes.children)) { if ($pc -and $pc.path -and $null -ne $pc.bytes) { $prevSizes[[string]$pc.path] = [int64]$pc.bytes; $prevHadSizes = $true } }
    }
    if (-not $SkipSizes) {
        $watched = @(
            (Join-Path $ProfileDir 'projects'),
            (Join-Path $env:APPDATA 'Claude'),
            (Join-Path $HomeDir '.codex'),
            (Join-Path $HomeDir 'Documents\Codex'),
            $DevRoot
        )
        foreach ($root in $watched) {
            $rsw = [System.Diagnostics.Stopwatch]::StartNew()
            if (-not (Test-PathSafe $root 'Container')) { $sizeRoots.Add([ordered]@{ path = $root; exists = $false; bytes = $null; looseFileBytes = $null; seconds = 0 }); continue }
            $looseBytes = [int64]0
            foreach ($lf in @(Get-ChildItem -LiteralPath $root -File -Force -ErrorAction SilentlyContinue)) { $looseBytes += $lf.Length }
            $rootBytes = $looseBytes
            foreach ($c in @(Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue)) {
                $cls = Get-FolderClass $c.FullName $c.Name
                $row = [ordered]@{ root = $root; path = $c.FullName; name = $c.Name; class = $cls; bytes = $null; files = $null; errors = 0; linksSkipped = 0; capHit = $false; skipped = $null; growthBytes = $null }
                if (Test-SkipByName $c.Name) { $row.skipped = 'skipped by rule (_Quarantine_)' }
                elseif (($c.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { $row.skipped = 'reparse point, not followed' }
                elseif (Test-Frozen $c.FullName) { $row.skipped = 'skipped by rule (FROZEN-DEPLOYMENT.md)' }
                else {
                    $m = Measure-Folder $c.FullName $SizeFileCap
                    $row.bytes = $m.Bytes; $row.files = $m.Files; $row.errors = $m.Errors; $row.linksSkipped = $m.LinksSkipped; $row.capHit = $m.CapHit
                    $rootBytes += $m.Bytes
                    if ($cls -eq 'unclassified' -and $m.Bytes -gt 1GB) {
                        Add-Finding 'sizes' ('Unclassified folder over 1 GB: ' + $c.FullName) ((Format-Bytes $m.Bytes) + ' (' + $m.Bytes + ' bytes, ' + $m.Files + ' files)')
                    }
                    if ($prevSizes.ContainsKey($c.FullName)) {
                        $row.growthBytes = $m.Bytes - $prevSizes[$c.FullName]
                        if ($row.growthBytes -gt 5GB) {
                            Add-Finding 'sizes' ('Folder grew by ' + (Format-Bytes $row.growthBytes) + ' since the previous run: ' + $c.FullName) ('bytes ' + $prevSizes[$c.FullName] + ' -> ' + $m.Bytes)
                        }
                    }
                    if ($m.CapHit) { $notes.Add('File cap of ' + $SizeFileCap + ' reached in ' + $c.FullName + '; its size is a lower bound.') }
                }
                $sizeChildren.Add($row)
            }
            $sizeRoots.Add([ordered]@{ path = $root; exists = $true; bytes = $rootBytes; looseFileBytes = $looseBytes; seconds = [math]::Round($rsw.Elapsed.TotalSeconds, 1) })
        }
    }
    $timings['sizes'] = [math]::Round($sw.Elapsed.TotalSeconds, 2)

    # -------------------------------------------------- 7. Summary and state
    $count = $script:Findings.Count
    $exitCode = 0
    if ($count -gt 0) { $exitCode = 1 }
    $finished = Get-Date
    $prevAt = $null
    if ($prev) { $prevAt = [string]$prev.generatedAt }

    $result = [ordered]@{
        schema      = 1
        tool        = 'Invoke-LibrarianCheck'
        generatedAt = (Format-Time $finished)
        seconds     = [math]::Round(($finished - $started).TotalSeconds, 1)
        parameters  = [ordered]@{ devRoot = $DevRoot; profileDir = $ProfileDir; hours = $Hours; stateDir = $StateDir; skipSizes = [bool]$SkipSizes; sizeTopN = $SizeTopN; sizeFileCap = $SizeFileCap; registerFile = $RegisterFile }
        previousRun = $prevAt
        findings    = $script:Findings.ToArray()
        profile     = [ordered]@{ files = $profileRows.ToArray() }
        hooks       = [ordered]@{ settingsFiles = $settingsRead.ToArray(); events = $hookEvents.ToArray(); paths = $hookPaths.ToArray(); commands = $hookCommands.ToArray() }
        transcripts = [ordered]@{ root = $projRoot; exists = $projExists; hours = $Hours; filesScanned = $scanned; unreadable = $unreadable; conversationMentions = $mentionTotal; files = $transcriptRows.ToArray() }
        worktrees   = [ordered]@{ git = $script:GitExe; repos = $repoRows.ToArray(); worktrees = $worktreeRows.ToArray(); unregistered = $unregisteredRows.ToArray(); retiredNests = $retiredRows.ToArray(); skippedByRule = $skippedRows.ToArray() }
        tasks       = [ordered]@{ listed = $tasksOk; registerFile = $RegisterFile; tasks = $taskRows.ToArray() }
        sizes       = [ordered]@{ skipped = [bool]$SkipSizes; fileCap = $SizeFileCap; previousHadSizes = $prevHadSizes; layout = $layoutRows.ToArray(); roots = $sizeRoots.ToArray(); children = $sizeChildren.ToArray() }
        notes       = $notes.ToArray()
        timings     = $timings
        summary     = [ordered]@{ findings = $count; exitCode = $exitCode }
    }
    $jsonText = ConvertTo-Json -InputObject $result -Depth 12

    # ---------------------------------------------- Markdown
    $md = New-Object 'System.Collections.Generic.List[string]'
    $md.Add('# Librarian check')
    $md.Add('')
    $md.Add('Generated ' + $result.generatedAt + ' in ' + $result.seconds + ' s. Read-only. DevRoot `' + $DevRoot + '`, ProfileDir `' + $ProfileDir + '`, transcript window ' + $Hours + ' h.')
    if ($prev) { $md.Add('Compared with the previous run from ' + $prevAt + ' (state folder `' + $StateDir + '`).') }
    else { $md.Add('No previous run in the state folder `' + $StateDir + '`; nothing to compare.') }
    $md.Add('')
    $md.Add('## Findings (' + $count + ')')
    $md.Add('')
    if ($count -eq 0) { $md.Add('- None.') }
    foreach ($f in $script:Findings) { $md.Add('- [' + $f.section + '] ' + $f.message + '. Receipt: ' + $f.receipt) }
    $md.Add('')

    $md.Add('## 1. Profile files')
    $md.Add('')
    $md.Add('| File | SHA-256 | Changed since previous run |')
    $md.Add('|---|---|---|')
    foreach ($p in $profileRows) {
        if (-not $p.exists -and -not $p.changed) { continue }
        $ch = 'no previous value'
        if ($p.changed -eq $true) { $ch = 'CHANGED (was ' + (Show-Hash $p.previousSha256) + ')' } elseif ($p.changed -eq $false) { $ch = 'no' }
        $md.Add('| `' + (ConvertTo-MdCell $p.path) + '` | ' + (Show-Hash $p.sha256) + ' | ' + $ch + ' |')
    }
    $absent = @($profileRows | Where-Object { -not $_.exists } | ForEach-Object { $_.name })
    if ($absent.Count -gt 0) { $md.Add(''); $md.Add('Not present: ' + ($absent -join ', ') + '.') }
    $md.Add('')

    $md.Add('## 2. Hooks')
    $md.Add('')
    if ($settingsRead.Count -eq 0) { $md.Add('No readable settings.json or settings.local.json under ProfileDir.') }
    else {
        $evText = @()
        foreach ($he in $hookEvents) {
            $tag = ''
            if ($he.source -like '*settings.local.json') { $tag = ' [settings.local.json]' }
            $evText += ($he.event + ' ' + $he.blocks + ' (' + $he.commands + ' commands)' + $tag)
        }
        if ($evText.Count -eq 0) { $md.Add('No hooks configured.') } else { $md.Add('Hook blocks per event: ' + ($evText -join '; ') + '.') }
        $md.Add('')
        if ($hookPaths.Count -eq 0) { $md.Add('No absolute script or folder paths found in hook commands.') }
        else {
            $md.Add('| Path | Kind | Exists | Events |')
            $md.Add('|---|---|---|---|')
            foreach ($g in $hookPaths) {
                $k = $g.kind
                if ($g.option) { $k = $k + ' (' + $g.option + ')' }
                $ex = 'NO'
                if ($g.exists) { $ex = 'yes' }
                $md.Add('| `' + (ConvertTo-MdCell $g.path) + '` | ' + $k + ' | ' + $ex + ' | ' + ($g.events -join ', ') + ' |')
            }
        }
    }
    $md.Add('')

    $md.Add('## 3. Hook errors in recent transcripts')
    $md.Add('')
    if (-not $projExists) { $md.Add('No projects folder at `' + $projRoot + '`.') }
    else {
        $md.Add('Scanned ' + $scanned + ' transcript files modified in the last ' + $Hours + ' h under `' + $projRoot + '` (unreadable: ' + $unreadable + '). Conversation lines that only mention the marker words: ' + $mentionTotal + ' (not counted as errors).')
        $md.Add('')
        if ($transcriptRows.Count -eq 0) { $md.Add('No hook error records found.') }
        else {
            $md.Add('| Transcript | Modified | hook_non_blocking_error lines | MODULE_NOT_FOUND lines |')
            $md.Add('|---|---|---|---|')
            foreach ($tr in $transcriptRows) { $md.Add('| `' + (ConvertTo-MdCell $tr.path) + '` | ' + $tr.modified + ' | ' + $tr.hookErrorLines + ' | ' + $tr.moduleNotFoundLines + ' |') }
        }
    }
    $md.Add('')

    $md.Add('## 4. Worktrees')
    $md.Add('')
    if (-not $devExists) { $md.Add('DevRoot `' + $DevRoot + '` not found.'); $md.Add('') }
    else {
        $okRepos = @($repoRows | Where-Object { $_.ok })
        $failRepos = @($repoRows | Where-Object { -not $_.ok })
        $md.Add('Repositories checked: ' + $okRepos.Count + ' (git failed: ' + $failRepos.Count + '). Linked worktrees: ' + $worktreeRows.Count + '. Allowed nests: `<repo>\.claude\worktrees`, `<repo>\.worktrees`, `' + $codexNest + '`, `' + $wtNest + '`.')
        $md.Add('')
        if ($worktreeRows.Count -gt 0) {
            $md.Add('| Worktree | Repo | Branch | Last commit | Dirty | In nest | Status |')
            $md.Add('|---|---|---|---|---|---|---|')
            foreach ($w in $worktreeRows) {
                $st = 'ok'
                if ($w.status.Count -gt 0) { $st = ($w.status -join ', ') }
                $dirtyText = 'n/a'
                if ($null -ne $w.dirty) { $dirtyText = [string]$w.dirty }
                $inNest = 'NO'
                if ($w.nest) { $inNest = 'yes' }
                $md.Add('| `' + (ConvertTo-MdCell $w.path) + '` | ' + (ConvertTo-MdCell (Split-Path -Leaf $w.repo)) + ' | ' + (ConvertTo-MdCell $w.branch) + ' | ' + $w.lastCommit + ' | ' + $dirtyText + ' | ' + $inNest + ' | ' + $st + ' |')
            }
            $md.Add('')
        }
        if ($unregisteredRows.Count -gt 0) {
            $md.Add('Unregistered folders in worktree nests:')
            foreach ($u in $unregisteredRows) { $md.Add('- `' + $u.path + '`') }
            $md.Add('')
        }
        if ($retiredRows.Count -gt 0) {
            $md.Add('Retired nests: ' + (($retiredRows | ForEach-Object { '`' + $_.path + '` (' + $_.entries + ' entries)' }) -join '; ') + '.')
            $md.Add('')
        }
        if ($skippedRows.Count -gt 0) {
            $md.Add('Skipped by rule: ' + (($skippedRows | ForEach-Object { '`' + $_.path + '` (' + $_.rule + ')' }) -join '; ') + '.')
            $md.Add('')
        }
    }

    $md.Add('## 5. Scheduled tasks')
    $md.Add('')
    if (-not $tasksOk) { $md.Add('Get-ScheduledTask failed; see findings.') }
    else {
        $regText = ''
        if ($RegisterFile) { $regText = ' Register: `' + $RegisterFile + '` (' + $regNames.Count + ' names).' }
        $md.Add('Non-Microsoft tasks: ' + $taskRows.Count + '. Results 0x0, 0x41301 (running) and 0x41303 (never run) count as healthy; disabled tasks are not judged on their result.' + $regText)
        $md.Add('')
        if ($RegisterFile) {
            $md.Add('| Task | State | Last run | Last result | Action path | Path exists | In register |')
            $md.Add('|---|---|---|---|---|---|---|')
        } else {
            $md.Add('| Task | State | Last run | Last result | Action path | Path exists |')
            $md.Add('|---|---|---|---|---|---|')
        }
        foreach ($t in $taskRows) {
            $ap = @()
            $ok = @()
            if ($t.execute) {
                $ap += $t.execute
                if ($t.executeExists) { $ok += 'yes' } else { $ok += 'NO' }
            }
            foreach ($pp in $t.paths) {
                $ap += $pp.path
                if ($pp.exists) { $ok += 'yes' } else { $ok += 'NO' }
            }
            if ($t.actionKind -eq 'com-handler') { $ap = @('(COM handler)'); $ok = @('n/a') }
            $runText = 'never'
            if ($t.lastRun) { $runText = $t.lastRun }
            $line = '| ' + (ConvertTo-MdCell $t.name) + ' | ' + $t.state + ' | ' + $runText + ' | ' + $t.lastResultHex + ' | ' + (ConvertTo-MdCell ($ap -join '; ')) + ' | ' + ($ok -join '; ') + ' |'
            if ($RegisterFile) {
                if ($t.inRegister) { $line += ' yes |' } else { $line += ' NO |' }
            }
            $md.Add($line)
        }
    }
    $md.Add('')

    $md.Add('## 6. Folder layout and sizes')
    $md.Add('')
    if ($devExists) {
        $bad = @($layoutRows | Where-Object { -not $_.allowed })
        $badText = ''
        if ($bad.Count -gt 0) { $badText = ' (' + (($bad | ForEach-Object { Split-Path -Leaf $_.path }) -join ', ') + ')' }
        $md.Add('DevRoot children: ' + $layoutRows.Count + '; outside the filing standard (repo, worktree nest, Archive, Tools, _wt): ' + $bad.Count + $badText + '.')
        $md.Add('')
    }
    if ($SkipSizes) { $md.Add('Sizes skipped (-SkipSizes).'); $md.Add('') }
    else {
        foreach ($r in $sizeRoots) {
            if (-not $r.exists) { $md.Add('### `' + $r.path + '`'); $md.Add(''); $md.Add('Not present.'); $md.Add(''); continue }
            $md.Add('### `' + $r.path + '` (' + (Format-Bytes $r.bytes) + ', ' + $r.seconds + ' s)')
            $md.Add('')
            $kids = @($sizeChildren | Where-Object { $_.root -eq $r.path })
            $top = @($kids | Where-Object { $null -ne $_.bytes } | Sort-Object { [int64]$_.bytes } -Descending | Select-Object -First $SizeTopN)
            $md.Add('Top ' + $top.Count + ' of ' + $kids.Count + ' child folders:')
            $md.Add('')
            $md.Add('| Folder | Size | Files | Class | Change since previous run | Notes |')
            $md.Add('|---|---|---|---|---|---|')
            foreach ($k in $top) {
                $nt = @()
                if ($k.capHit) { $nt += 'file cap hit' }
                if ($k.errors -gt 0) { $nt += ('' + $k.errors + ' unreadable folders') }
                if ($k.linksSkipped -gt 0) { $nt += ('' + $k.linksSkipped + ' links not followed') }
                $gr = 'n/a'
                if ($null -ne $k.growthBytes) {
                    if ($k.growthBytes -ge 0) { $gr = '+' + (Format-Bytes $k.growthBytes) } else { $gr = '-' + (Format-Bytes (-1 * $k.growthBytes)) }
                }
                $md.Add('| ' + (ConvertTo-MdCell $k.name) + ' | ' + (Format-Bytes $k.bytes) + ' | ' + $k.files + ' | ' + $k.class + ' | ' + $gr + ' | ' + ($nt -join '; ') + ' |')
            }
            $sk = @($kids | Where-Object { $_.skipped })
            if ($sk.Count -gt 0) { $md.Add(''); $md.Add('Not measured: ' + (($sk | ForEach-Object { $_.name + ' (' + $_.skipped + ')' }) -join '; ') + '.') }
            $md.Add('')
        }
        if (-not $prevHadSizes) { $md.Add('The previous run has no sizes, so growth was not compared.'); $md.Add('') }
    }

    $md.Add('## 7. Summary')
    $md.Add('')
    foreach ($nn in $notes) { $md.Add('- Note: ' + $nn) }
    if ($notes.Count -gt 0) { $md.Add('') }
    $md.Add('Section seconds: ' + (($timings.Keys | ForEach-Object { $_ + ' ' + $timings[$_] }) -join ', ') + '.')
    $md.Add('')
    $md.Add('Findings: ' + $count + '. Exit code: ' + $exitCode + '.')
    $mdText = ($md -join "`r`n") + "`r`n"

    # ---------------------------------------------- write state (the only writes)
    if (-not (Test-PathSafe $StateDir 'Container')) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }
    $utf8 = New-Object System.Text.UTF8Encoding $false
    if (Test-PathSafe $latestPath 'Leaf') { [System.IO.File]::Copy($latestPath, $previousPath, $true) }
    [System.IO.File]::WriteAllText($latestPath, $jsonText, $utf8)
    if ($OutFile) { [System.IO.File]::WriteAllText($OutFile, $mdText, $utf8) }

    if ($Json) { Write-Output $jsonText } else { Write-Output $mdText }
    exit $exitCode
} catch {
    [Console]::Error.WriteLine('Invoke-LibrarianCheck failed: ' + $_.Exception.Message)
    if ($_.InvocationInfo) { [Console]::Error.WriteLine($_.InvocationInfo.PositionMessage) }
    exit 2
}
