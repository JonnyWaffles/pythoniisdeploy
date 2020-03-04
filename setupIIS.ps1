
Param(
    [Parameter(
        Mandatory=$true,
        HelpMessage="The name of the website"
        )]
    [ValidateNotNullOrEmpty()]
    [String]
    $siteName,

    [Parameter(
        ParameterSetName="Implicit"
    )]
    [String]
    $projectRoot = $(Split-Path $script:MyInvocation.MyCommand.Path | Split-Path),
    
    [Parameter(
        ParameterSetName="Implicit"
    )]
    [String]
    $venvFolderName = "venv",

    [Parameter(
        HelpMessage="Explicitly set the Pythonpath"
    )]
    [String]
    $pythonPath = $([IO.Path]::Combine($projectRoot, $venvFolderName, 'Scripts\Python.exe')),

    [Parameter(
        HelpMessage="Set WSGI handler. Must be an importable Python callable."
    )]
    [String]
    $wsgiHandler = "app"
)

# IIS Requires absolute paths
$pythonPath = Resolve-Path $pythonPath
$projectRoot = Resolve-Path $projectRoot
$wfastcgiPath = Join-Path $(Split-Path $pythonPath | Split-Path) "Lib\site-packages\wfastcgi.py"

if (!$pythonPath) {
    throw "pythonPath could not be determined and must be provided."
}

if (!$projectRoot) {
    throw "projectRoot could not be determined and must be provided."
}

if (!$wfastcgiPath) {
    throw "wfastcgiPath cannot be empty string."
}

Write-Verbose "`npythonPath: $pythonPath `n projectRoot: $projectRoot `n wfastcgiPath: $wfastcgiPath"


function checkIISReady {
    $featureOperationResult = Install-WindowsFeature -name Web-Server -IncludeManagementTools
    if ($featureOperationResult.RestartNeeded -ne "No") {
        throw "A a restart is required. Please reboot the target machine and re-run the deployment."
    }
    $iisInfo = Get-ItemProperty -Path registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\InetStp\ |
        Select-Object -Property MajorVersion
    if ($iisInfo.MajorVersion -lt 7) {
        throw "IIS Version must be greater than 7 to use fastcgi!"
    }
    $imageObj = Enable-WindowsOptionalFeature -Online -FeatureName IIS-CGI
    if ($imageObj.RestartNeeded) {
        throw "A a restart is required. Please reboot the target machine and re-run the deployment."
    }
}

function setupSite {
    Write-Verbose "Begin $siteName Website Setup"
    $site = Get-Website $siteName
    if (!$site) {

        $applicationPoolName = "$siteName Application Pool"
        
        New-WebAppPool -Name $applicationPoolName -Force

        $siteParams = @{
            name = $siteName;
            port = 80;
            ApplicationPool = $applicationPoolName;
            PhysicalPath = $projectRoot
        }
        $site = New-Website @siteParams
    }
    $psPath = "IIS:\sites\$siteName"
    $handlerName = 'Python FastCGI'
    <# For some insane reason powershell disregards the psPath parameter.
        The only way to add the handler to the webconfig and not the apphost config is to change
        the directory.
        #>
    Write-Verbose "psPath is $psPath"
    Push-Location $psPath
    Write-Verbose "Location pushed. Now in $(Get-Location)"

    $handler = Get-WebHandler -Name $handlerName
    if (!$handler) {
        Write-Verbose "Adding New Webhandler"
        $kwargs = @{
            Name = $handlerName;
            Path = "*";
            Verb = "*";
            Modules = "FastCgiModule";
            scriptProcessor = "$pythonPath|$wfastcgiPath";
            resourceType = "Unspecified";
            requiredAccess = "Script"
        }
        New-WebHandler @kwargs
    } else {
        Write-Verbose "Web Handler $handlerName already exists"
    }
    Pop-Location
    Write-Verbose "Location popped. Now in $(Get-Location)"
    $appsettings = Get-WebConfiguration 'appSettings/add' -PSPath $psPath
    if (!$appsettings) {
        Add-WebConfiguration 'appSettings' -PSPath $psPath  -Value @{key="WSGI_HANDLER"; value=$wsgiHandler}
        Add-WebConfiguration 'appSettings' -PSPath $psPath  -Value @{key="PYTHONPATH"; value=$projectRoot}
    }
}

function setupFastCGI
{
    Write-Verbose "Setting up fastCGI on the appHost"
    if (!(Test-Path $wfastcgiPath)) {
        throw "Wfastcgi script not found at $wfastcgiPath. Pip install it."
    }

    $fastcgi = Get-WebConfiguration -Filter "system.webServer/fastCgi/*" -PSPath "IIS:\" -Recurse |
        where-object { $_.fullPath -eq $pythonPath }
        
    if (!$fastcgi) {
        Write-Verbose "Adding fastCGI settings"
        Add-WebConfiguration "system.webServer/fastcgi" -PSPath "IIS:\" -Value @{
            "fullPath" = $pythonPath;
            "arguments" = $wfastcgiPath
        }
    }
}

function main
{    
    checkIISReady
    setupFastCGI
    setupSite
}

main
