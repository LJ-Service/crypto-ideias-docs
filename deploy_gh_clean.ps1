Param(
    [string]$Message = $("docs: deploy " + (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss 'UTC'")),
    [string]$RepoName = "crypto-ideias-docs",
    [ValidateSet("public","private")][string]$Visibility = "public",
    [string]$DefaultBranch = "main"
)

function Require-Cmd($name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        Write-Error ("Command not found: " + $name + ". Install it and try again.")
        exit 1
    }
}

# Requirements
Require-Cmd git
Require-Cmd gh

# Initialize repo if needed
if (-not (Test-Path ".git")) {
    Write-Host "Initializing git repository..."
    git init | Out-Null
    try {
        git checkout -b $DefaultBranch 2>$null | Out-Null
    } catch {
        git branch -M $DefaultBranch | Out-Null
    }
}

# Check remote origin
$hasOrigin = $false
try {
    $null = git remote get-url origin 2>$null
    if ($LASTEXITCODE -eq 0) { $hasOrigin = $true }
} catch {
    $hasOrigin = $false
}

if (-not $hasOrigin) {
    # GitHub auth
    $user = (& gh api user --jq ".login" 2>$null)
    if (-not $user) {
        Write-Error "Not authenticated in GitHub CLI. Run: gh auth login"
        exit 1
    }

    $repoFull = "$user/$RepoName"

    # If repo does not exist, create
    $exists = $true
    try {
        & gh repo view $repoFull 1>$null 2>$null
        if ($LASTEXITCODE -ne 0) { $exists = $false }
    } catch {
        $exists = $false
    }

    if (-not $exists) {
        Write-Host ("Creating repository " + $repoFull + " (" + $Visibility + ") ...")
        & gh repo create $repoFull --$Visibility --source=. --disable-issues --disable-wiki --confirm
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to create repository with GitHub CLI."
            exit 1
        }
    } else {
        Write-Host ("Repository " + $repoFull + " already exists. Adding remote...")
        git remote add origin "https://github.com/$repoFull.git" 2>$null | Out-Null
    }
}

# Add & commit
git add -A | Out-Null
$hasChanges = $true
try {
    git diff --cached --quiet
    if ($LASTEXITCODE -eq 0) { $hasChanges = $false }
} catch {
    $hasChanges = $true
}

if ($hasChanges) {
    git commit -m $Message | Out-Null
} else {
    Write-Host "No changes to commit."
}

# Ensure origin exists
try {
    $null = git remote get-url origin 2>$null
} catch {
    $user = (& gh api user --jq ".login")
    git remote add origin "https://github.com/$user/$RepoName.git" | Out-Null
}

# Push
git push -u origin $DefaultBranch
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to push. Check repository permissions and try again."
    exit 1
}

# Enable GitHub Pages via API (root on main)
try {
    $remoteUrl = git remote get-url origin
    $repoPath = $remoteUrl -replace "^(git@github.com:|https://github.com/)", "" -replace "\.git$",""
    $owner = $repoPath.Split("/")[0]
    $name  = $repoPath.Split("/")[1]

    Write-Host "Attempting to enable GitHub Pages (root on main)..."
    gh api -X PUT ("repos/" + $owner + "/" + $name + "/pages") -f build_type=legacy 1>$null 2>$null
    gh api -X POST ("repos/" + $owner + "/" + $name + "/pages/builds") 1>$null 2>$null

    $pagesUrl = "https://" + $owner + ".github.io/" + $name + "/"
    Write-Host ""
    Write-Host "Deploy completed."
    Write-Host ("GitHub Pages (wait ~1-2 min): " + $pagesUrl)
    Write-Host ("Privacy Policy: " + $pagesUrl + "politica.html")
    Write-Host ("Terms of Use:  " + $pagesUrl + "termos.html")
} catch {
    Write-Warning "Could not enable Pages automatically. Enable manually in Settings -> Pages (Branch: main, Folder: /(root))."
}
