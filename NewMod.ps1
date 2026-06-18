<#
.SYNOPSIS
    从 Moss-Template 创建新的 Casualties Unknown 模组项目。

.DESCRIPTION
    使用 dotnet new mosstemplate 模板生成新模组项目，并自动配置所有参数。
    自动检测 Steam 安装路径中的游戏 Managed 目录。

.PARAMETER ModName
    模组的 PascalCase 命名空间名称（如 "MyCoolMod"），将作为项目名和命名空间。
    不能包含空格。

.PARAMETER ModDisplayName
    模组的显示名称（如 "My Cool Mod"），用于 BepInEx 插件注册。
    如果不指定，将自动从 ModName 按大驼峰拆分生成。

.PARAMETER ModGuid
    模组的唯一 GUID，格式为 "yourname.modname"（如 "com.example.mycoolmod"）。

.PARAMETER ModVersion
    模组的初始版本号（如 "1.0.0"）。

.PARAMETER AuthorName
    作者名称，用于 LICENSE 文件。

.PARAMETER GameManagedDir
    游戏 Managed 目录的完整路径。如果不指定，将自动从 Steam 常见安装路径中检测。

.PARAMETER OutputDir
    项目输出目录。如果不指定，则使用当前目录下与 ModName 同名的子目录。

.EXAMPLE
    .\NewMod.ps1 -ModName "MyCoolMod" -ModGuid "com.example.mycoolmod"

.EXAMPLE
    .\NewMod.ps1
    # 交互式输入所有参数，自动检测游戏路径

.NOTES
    需要已安装 .NET SDK 并注册了 mosstemplate 模板。
    注册命令: dotnet new install <模板项目路径>
#>
param(
    [string]$ModName,
    [string]$ModDisplayName,
    [string]$ModGuid,
    [string]$ModVersion,
    [string]$AuthorName,
    [string]$GameManagedDir,
    [string]$OutputDir
)

# ============================================================
# 辅助函数
# ============================================================

function Convert-ToDisplayName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $Name }
    $result = [System.Text.StringBuilder]::new()
    $chars = $Name.ToCharArray()
    for ($i = 0; $i -lt $chars.Length; $i++) {
        $c = $chars[$i]
        if ($i -gt 0 -and [char]::IsUpper($c) -and [char]::IsLower($chars[$i - 1])) {
            $result.Append(' ') | Out-Null
        }
        $result.Append($c) | Out-Null
    }
    return $result.ToString()
}

function Read-Input {
    param(
        [string]$Prompt,
        [string]$DefaultValue,
        [switch]$Required
    )
    if ($DefaultValue) {
        $userInput = Read-Host "$Prompt (默认: $DefaultValue)"
        if ([string]::IsNullOrWhiteSpace($userInput)) { return $DefaultValue }
    } else {
        $userInput = Read-Host $Prompt
    }
    if ($Required -and [string]::IsNullOrWhiteSpace($userInput)) {
        Write-Error "此项为必填项，请重新运行脚本并提供有效值。"
        exit 1
    }
    return $userInput
}

function Find-GameManagedDir {
    $gameRelativePath = "steamapps\common\Casualties Unknown Demo\CasualtiesUnknown_Data\Managed"

    $steamCandidates = @(
        "C:\Program Files (x86)\Steam",
        "D:\SteamLibrary",
        "E:\SteamLibrary",
        "F:\SteamLibrary",
        "D:\Steam",
        "E:\Steam",
        "F:\Steam"
    )

    try {
        $steamRegPath = Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -Name "InstallPath" -ErrorAction SilentlyContinue
        if ($steamRegPath -and $steamRegPath.InstallPath) {
            $steamCandidates = @($steamRegPath.InstallPath) + $steamCandidates
        }
    } catch { }

    $libraryFolders = @()
    foreach ($steamRoot in $steamCandidates) {
        $vdfPath = Join-Path $steamRoot "steamapps\libraryfolders.vdf"
        if (Test-Path $vdfPath) {
            try {
                $vdfContent = Get-Content $vdfPath -Raw
                $pattern = '"path"\s+"(.+?)"'
                $vdfMatches = [regex]::Matches($vdfContent, $pattern)
                foreach ($m in $vdfMatches) {
                    $libPath = $m.Groups[1].Value -replace '\\\\', '\'
                    if (-not $libraryFolders.Contains($libPath)) {
                        $libraryFolders += $libPath
                    }
                }
            } catch { }
        }
    }

    $allCandidates = @()
    foreach ($lib in $libraryFolders) {
        $allCandidates += Join-Path $lib $gameRelativePath
    }
    foreach ($steamRoot in $steamCandidates) {
        $allCandidates += Join-Path $steamRoot $gameRelativePath
    }

    foreach ($candidate in $allCandidates) {
        $normalizedPath = $candidate.Replace('\', '/')
        if (Test-Path $normalizedPath -PathType Container) {
            return $normalizedPath
        }
    }

    return $null
}

# ============================================================
# 设置编码
# ============================================================
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 > $null

# ============================================================
# 交互式输入缺失的参数
# ============================================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Casualties Unknown Mod Creator" -ForegroundColor Cyan
Write-Host "  Moss-Template 模组创建向导" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ([string]::IsNullOrWhiteSpace($ModName)) {
    $ModName = Read-Input -Prompt "输入模组命名空间 (PascalCase, 不能有空格, 如 MyCoolMod)" -Required
}

if ($ModName -match '\s') {
    Write-Error "命名空间不能包含空格: '$ModName'"
    exit 1
}

if ([string]::IsNullOrWhiteSpace($ModDisplayName)) {
    $autoDisplayName = Convert-ToDisplayName -Name $ModName
    $ModDisplayName = Read-Input -Prompt "输入模组显示名称" -DefaultValue $autoDisplayName
}

if ([string]::IsNullOrWhiteSpace($ModGuid)) {
    $defaultGuid = "com.example.$($ModName.ToLower())"
    $ModGuid = Read-Input -Prompt "输入模组 GUID (格式: yourname.modname)" -DefaultValue $defaultGuid -Required
}

if ([string]::IsNullOrWhiteSpace($ModVersion)) {
    $ModVersion = Read-Input -Prompt "输入模组版本号" -DefaultValue "1.0.0"
}

if ([string]::IsNullOrWhiteSpace($AuthorName)) {
    $AuthorName = Read-Input -Prompt "输入作者名称 (用于 LICENSE)" -DefaultValue "Your Name"
}

if ([string]::IsNullOrWhiteSpace($GameManagedDir)) {
    Write-Host ""
    Write-Host "正在搜索 Casualties Unknown 游戏路径..." -ForegroundColor Cyan

    $detectedPath = Find-GameManagedDir

    if ($detectedPath) {
        Write-Host "  已找到游戏目录: $detectedPath" -ForegroundColor Green
        $GameManagedDir = Read-Input -Prompt "输入游戏 Managed 目录路径" -DefaultValue $detectedPath
    } else {
        Write-Host "  未自动找到游戏目录，请手动输入。" -ForegroundColor Yellow
        $GameManagedDir = Read-Input -Prompt "输入游戏 Managed 目录路径" -Required
    }
}

$normalizedGameDir = $GameManagedDir.Replace('\', '/')
if (-not (Test-Path $normalizedGameDir -PathType Container)) {
    Write-Warning "游戏目录不存在: $GameManagedDir"
    Write-Warning "项目将被创建，但你需要手动修改 csproj 中的 DLL 引用路径。"
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Read-Input -Prompt "输入项目输出目录" -DefaultValue $ModName
}

# ============================================================
# 显示配置摘要
# ============================================================

Write-Host ""
Write-Host "----------------------------------------" -ForegroundColor Yellow
Write-Host "配置摘要:" -ForegroundColor Yellow
Write-Host "  命名空间/项目名: $ModName" -ForegroundColor White
Write-Host "  显示名称:        $ModDisplayName" -ForegroundColor White
Write-Host "  GUID:            $ModGuid" -ForegroundColor White
Write-Host "  版本号:          $ModVersion" -ForegroundColor White
Write-Host "  作者:            $AuthorName" -ForegroundColor White
Write-Host "  游戏目录:        $GameManagedDir" -ForegroundColor White
Write-Host "  输出目录:        $OutputDir" -ForegroundColor White
Write-Host "----------------------------------------" -ForegroundColor Yellow
Write-Host ""

$confirm = Read-Host "确认创建? (Y/n)"
if ($confirm -eq 'n' -or $confirm -eq 'N') {
    Write-Host "已取消。" -ForegroundColor Red
    exit 0
}

# ============================================================
# 执行 dotnet new
# ============================================================

Write-Host ""
Write-Host "正在创建项目..." -ForegroundColor Cyan

$GameManagedDirNormalized = $GameManagedDir.Replace('\', '/')

$dotnetArgs = @(
    "new", "mosstemplate",
    "-n", $ModName,
    "--ModDisplayName", $ModDisplayName,
    "--ModGuid", $ModGuid,
    "--ModVersion", $ModVersion,
    "--AuthorName", $AuthorName,
    "--GameManagedDir", $GameManagedDirNormalized,
    "-o", $OutputDir
)

Write-Host "  执行: dotnet $($dotnetArgs -join ' ')" -ForegroundColor DarkGray
Write-Host ""

& dotnet @dotnetArgs

if ($LASTEXITCODE -ne 0) {
    Write-Error "dotnet new 执行失败 (退出码: $LASTEXITCODE)"
    Write-Host ""
    Write-Host "如果 mosstemplate 模板未安装，请先执行以下命令注册:" -ForegroundColor Yellow
    Write-Host "  dotnet new install <Moss-Template 项目路径>" -ForegroundColor Yellow
    exit $LASTEXITCODE
}

# ============================================================
# 清理模板 Git 并初始化新仓库
# ============================================================

$projectPath = Resolve-Path $OutputDir

$oldGitDir = Join-Path $projectPath ".git"
if (Test-Path $oldGitDir) {
    Write-Host "清理模板 Git 仓库..." -ForegroundColor Cyan
    Remove-Item -Recurse -Force $oldGitDir
}

Write-Host "初始化新 Git 仓库..." -ForegroundColor Cyan
Push-Location $projectPath
try {
    git init | Out-Null
    git add . | Out-Null
    git commit -m "Initial commit: $ModDisplayName mod" | Out-Null
    Write-Host "  Git 仓库已初始化并完成首次提交。" -ForegroundColor Green
} catch {
    Write-Warning "Git 初始化失败: $_"
}
Pop-Location

# ============================================================
# 生成 Rider 运行配置
# ============================================================

Write-Host "生成 Rider 运行配置..." -ForegroundColor Cyan

$gameRootPath = (Resolve-Path (Join-Path $normalizedGameDir "..\..")).Path
$gameRootPath = $gameRootPath.Replace('\', '/')

$runDir = Join-Path $projectPath ".run"
if (-not (Test-Path $runDir)) {
    New-Item -ItemType Directory -Path $runDir -Force | Out-Null
}

$runConfig = @"
<component name="ProjectRunConfigurationManager">
  <configuration default="false" name="StartGame" type="PowerShellRunType" factoryName="PowerShell" scriptUrl="`$PROJECT_DIR$/StartGame.ps1" scriptParameters=""$gameRootPath" "$ModName"" commandOptions="-ExecutionPolicy Bypass" executablePath="C:/WINDOWS/System32/WindowsPowerShell/v1.0/powershell.exe">
    <envs />
    <method v="2">
      <option name="Build Solution" enabled="true" />
    </method>
  </configuration>
</component>
"@

$runConfigPath = Join-Path $runDir "StartGame.run.xml"
[System.IO.File]::WriteAllText($runConfigPath, $runConfig, [System.Text.UTF8Encoding]::new($true))
Write-Host "  已创建: .run/StartGame.run.xml" -ForegroundColor Green

# ============================================================
# 完成
# ============================================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  项目创建成功!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "下一步:" -ForegroundColor Yellow
Write-Host "  1. cd $OutputDir" -ForegroundColor White
Write-Host "  2. dotnet build  (验证编译)" -ForegroundColor White
Write-Host "  3. 右键 StartGame.ps1 运行测试" -ForegroundColor White
Write-Host ""
