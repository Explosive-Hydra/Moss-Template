param(
    [string]$GamePath,
    [string]$ModNamespace
)

# 自动从命名空间生成显示名称（仅在大写字母前加空格，前提是该大写字母前面是小写字母）
function Convert-ToDisplayName {
    param([string]$Namespace)
    if ([string]::IsNullOrWhiteSpace($Namespace)) { return $Namespace }

    $result = [System.Text.StringBuilder]::new()
    $chars = $Namespace.ToCharArray()
    for ($i = 0; $i -lt $chars.Length; $i++) {
        $c = $chars[$i]
        # 如果当前字符是大写，且前一个字符是小写，则先插入空格
        if ($i -gt 0 -and [char]::IsUpper($c) -and [char]::IsLower($chars[$i-1])) {
            $result.Append(' ') | Out-Null
        }
        $result.Append($c) | Out-Null
    }
    return $result.ToString()
}

$ModName = Convert-ToDisplayName -Namespace $ModNamespace

# 设置编码为 UTF-8
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 强制设置当前代码页为 UTF-8 (65001)
chcp 65001 > $null

# 获取时间戳
$timestamp = Get-Date -Format "yyyy-MM-dd_HH.mm.ss"

# 各种路径
$GamePath = [System.IO.Path]::GetFullPath($GamePath) # 游戏路径
$bepInExPath = [System.IO.Path]::Combine($GamePath, "BepInEx")

# 各种文件
$GameLog = Join-Path $env:USERPROFILE "AppData\LocalLow\Orsoniks\CasualtiesUnknown\Player.log" # 游戏日志
$GameExecutable = [System.IO.Path]::Combine($GamePath, "CasualtiesUnknown.exe") # 游戏文件
$ModDll = [System.IO.Path]::Combine($PSScriptRoot, "bin/Debug/net472", "$ModNamespace.dll")

# 统一使用 ModName 作为目标文件夹名称
$targetModFolder = $ModName

# 文档文件列表
$docFiles = @("README.md", "README_ZH.md", "LICENSE.md", "Cover.png")

# 日志目标路径
$logDestination = [System.IO.Path]::Combine($PSScriptRoot, "Logs", "$timestamp.log") # 日志目标路径

# 检查游戏路径是否有效
if (-not (Test-Path $GamePath -PathType Container))
{
    Write-Error "游戏路径无效或不是目录: $GamePath"
    exit 1
}

# 确保目标目录存在
$logsFolder = [System.IO.Path]::Combine($PSScriptRoot, "Logs")
if (-not (Test-Path $logsFolder))
{
    New-Item -ItemType Directory -Path $logsFolder -Force
}

# 封装输出函数
function Write-ColoredMessage
{
    param (
        [string]$Message,
        [System.ConsoleColor]$Color
    )
    Write-Host $Message -ForegroundColor $Color
}

# 定义日志复制函数
function Copy-BepInExLog
{
    if (Test-Path $GameLog)
    {
        try
        {
            Copy-Item $GameLog $logDestination -Force
            Write-ColoredMessage "正在复制 BepInEx 日志到 ""$logDestination""。" Cyan
        }
        catch
        {
            Write-Warning "复制 BepInEx 日志失败: $_"
        }
    }
}

# 间隔输出
function Interval
{
    Write-Host "----------------------------------------"
}

# 清空 BepInEx 日志文件
if (Test-Path $GameLog)
{
    Clear-Content $GameLog
    Write-ColoredMessage "已清空之前的日志文件。" Cyan
}

# 输出启动信息
Write-ColoredMessage "游戏路径: $GamePath" Yellow
Write-ColoredMessage "模组命名空间: $ModNamespace" Yellow
Write-ColoredMessage "模组名称: $ModName" Yellow
Write-ColoredMessage "目标文件夹: $targetModFolder" Yellow

# 复制dll文件到游戏目录 - 统一使用 ModName 文件夹
try
{
    $pluginPath = [System.IO.Path]::Combine($bepInExPath, "plugins", $targetModFolder)
    New-Item -ItemType Directory -Path $pluginPath -Force
    Copy-Item $ModDll ([System.IO.Path]::Combine($pluginPath, "$ModNamespace.dll")) -Force
    Write-ColoredMessage "正在复制模组 DLL 到 ""$pluginPath\$ModNamespace.dll""。" Cyan
}
catch
{
    Write-Error "复制模组 DLL 失败: $_"
    exit 1
}

# 复制文档文件到插件目录
try
{
    $destDocPath = [System.IO.Path]::Combine($bepInExPath, "plugins", $targetModFolder)
    $copiedDocs = 0

    foreach ($docFile in $docFiles)
    {
        $sourceDocPath = [System.IO.Path]::Combine($PSScriptRoot, $docFile)
        $destDocFilePath = [System.IO.Path]::Combine($destDocPath, $docFile)

        if (Test-Path $sourceDocPath -PathType Leaf)
        {
            Copy-Item $sourceDocPath $destDocFilePath -Force
            Write-ColoredMessage "正在复制文档文件 ""$docFile"" 到 ""$destDocFilePath""。" Cyan
            $copiedDocs++
        }
        else
        {
            Write-ColoredMessage "文档文件 ""$docFile"" 不存在，跳过。" Yellow
        }
    }

    if ($copiedDocs -gt 0)
    {
        Write-ColoredMessage "已成功复制 $copiedDocs 个文档文件到插件目录。" Green
    }
}
catch
{
    Write-Warning "复制文档文件失败: $_"
}

# 启动游戏进程并重定向输出
try
{
    $gameProcess = Start-Process -FilePath $GameExecutable `
        -WorkingDirectory (Split-Path $GameExecutable -Parent) `
        -PassThru -NoNewWindow

    Write-ColoredMessage "游戏进程已启动, PID: $( $gameProcess.Id )" Yellow
    Interval

    # 定期轮询日志
    $lastReadPosition = 0
    while (!$gameProcess.HasExited)
    {
        if (Test-Path $GameLog)
        {
            $content = Get-Content $GameLog -ReadCount 0 -Encoding UTF8
            for ($i = $lastReadPosition; $i -lt $content.Count; $i++) {
                Write-ColoredMessage $content[$i] Magenta
            }
            $lastReadPosition = $content.Count
        }
        Start-Sleep -Milliseconds 500 # 每 500ms 检查一次
    }

    # 等待游戏进程退出
    Interval
    Write-ColoredMessage "游戏进程已退出。" Red
}

catch
{
    Write-Error "启动游戏进程失败: $_"
    exit 1
}

finally
{
    # 如果游戏进程仍在运行，则终止它
    if ($gameProcess -and !$gameProcess.HasExited)
    {
        Interval
        Write-ColoredMessage "正在终止游戏进程..." Red
        $gameProcess.Kill()
    }
    Copy-BepInExLog
}
