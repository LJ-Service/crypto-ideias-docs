Param(
    [string]$Message = $("docs: deploy " + (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss 'UTC'")),
    [string]$RepoName = "crypto-ideias-docs",
    [ValidateSet("public","private")][string]$Visibility = "public",
    [string]$DefaultBranch = "main"
)

function Require-Cmd($name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        Write-Error "❌ '$name' não encontrado. Instale e tente novamente."
        exit 1
    }
}

# Requisitos
Require-Cmd git
Require-Cmd gh

# Inicializa repositório se necessário
if (-not (Test-Path ".git")) {
    Write-Host "Inicializando repositório git..." -ForegroundColor Cyan
    git init | Out-Null
    # Define/garante a branch padrão
    try {
        git checkout -b $DefaultBranch 2>$null | Out-Null
    } catch {
        git branch -M $DefaultBranch | Out-Null
    }
}

# Verifica remote origin; cria repo com gh se não existir
$hasOrigin = $false
try {
    $null = git remote get-url origin 2>$null
    if ($LASTEXITCODE -eq 0) { $hasOrigin = $true }
} catch { $hasOrigin = $false }

if (-not $hasOrigin) {
    # Autenticação GH
    $user = (& gh api user --jq ".login" 2>$null)
    if (-not $user) {
        Write-Error "❌ Não autenticado no GitHub CLI. Rode: gh auth login"
        exit 1
    }

    # Verifica se repo existe; se não, cria
    $repoFull = "$user/$RepoName"
    $exists = $true
    try {
        & gh repo view $repoFull 1>$null 2>$null
        if ($LASTEXITCODE -ne 0) { $exists = $false }
    } catch { $exists = $false }

    if (-not $exists) {
        Write-Host "🚀 Criando repositório $repoFull ($Visibility)..." -ForegroundColor Cyan
        & gh repo create $repoFull --$Visibility --source=. --disable-issues --disable-wiki --confirm
        if ($LASTEXITCODE -ne 0) {
            Write-Error "❌ Falha ao criar repositório com gh."
            exit 1
        }
    } else {
        Write-Host "ℹ️ Repositório $repoFull já existe. Adicionando remote..." -ForegroundColor Yellow
        git remote add origin "https://github.com/$repoFull.git" 2>$null | Out-Null
    }
}

# Add & commit
git add -A | Out-Null
$hasChanges = $true
try {
    git diff --cached --quiet
    if ($LASTEXITCODE -eq 0) { $hasChanges = $false }
} catch { }

if ($hasChanges) {
    git commit -m $Message | Out-Null
} else {
    Write-Host "Nenhuma alteração para commit." -ForegroundColor Yellow
}

# Garante remote origin configurado
try {
    $null = git remote get-url origin 2>$null
} catch {
    # Se ainda não houver origin, define agora
    $user = (& gh api user --jq ".login")
    git remote add origin "https://github.com/$user/$RepoName.git" | Out-Null
}

# Push
git push -u origin $DefaultBranch
if ($LASTEXITCODE -ne 0) {
    Write-Error "❌ Falha ao fazer push. Verifique permissões do repositório e tente novamente."
    exit 1
}

# Habilitar GitHub Pages via API (root na main)
try {
    $remoteUrl = git remote get-url origin
    $repoPath = $remoteUrl -replace "^(git@github.com:|https://github.com/)", "" -replace "\.git$",""
    $owner = $repoPath.Split("/")[0]
    $name  = $repoPath.Split("/")[1]

    Write-Host "Ativando GitHub Pages..." -ForegroundColor Cyan
    # Alguns ambientes exigem permissões elevadas; ignore erros silenciosamente
    gh api -X PUT "repos/$owner/$name/pages" -f build_type=legacy 1>$null 2>$null
    gh api -X POST "repos/$owner/$name/pages/builds" 1>$null 2>$null

    $pagesUrl = "https://$owner.github.io/$name/"
    Write-Host ""
    Write-Host "✅ Deploy concluído." -ForegroundColor Green
    Write-Host "🌐 GitHub Pages (aguarde ~1–2 min): $pagesUrl"
    Write-Host "🔗 Política: ${pagesUrl}politica.html"
    Write-Host "🔗 Termos:   ${pagesUrl}termos.html"
} catch {
    Write-Warning "⚠️ Não foi possível ativar o Pages automaticamente. Ative manualmente em Settings → Pages (Branch: main, Folder: /(root))."
}
