function Install-ModuleFromGitHub {
    <#
    .SYNOPSIS
    Install-ModuleFromGitHub.ps1 - Adds cmdlets for direct installing mods from GitHub. Works similar to Install-Module. It streamlines the multi-step process of downloading the zip from GitHub, unblocking it, unzipping it and copying it to a well known module directory. It also checks for a ‘psd1’ file, cracks is open and uses the ModuleVersion to create a directory for it to copy the bits to.
    .NOTES
    Version     : 1.6.2
    Author      : Doug Finke
    Website     : https://github.com/dfinke/InstallModuleFromGitHub
    Twitter     : @dfinke / http://twitter.com/dfinke
    CreatedDate : 2024-01-11
    FileName    : Install-ModuleFromGitHub.ps1
    License     : Apache License
    Copyright   : Copyright 2016 Doug Finke
    Github      : https://github.com/tostka/InstallModuleFromGitHub
    Tags        : Powershell,Module,Install,Github
    AddedCredit : Todd Kadrie
    AddedWebsite: http://www.toddomation.com
    AddedTwitter: @tostka / http://twitter.com/tostka
    REVISIONS
    * 10:58 AM 1/12/2024 1.6.2 add: expand error cap on invoke-restmehtod; reworked 
        new-modulemanifest process, try/Catch test-ModuleManifest, push 
        New-ModuleManifest rebuild into the catch (rather than just driving if missing 
        ModuleVersion; should force rebuild on any test fail) 
        Test existintg .psd1 key add, and append any keys in the extracted, into the new recreation 
        Considered sticking ProjectURI, Tags, in the new, but new-MM throws up if they're $null (and pulling them out is a waste of space; auto-append will add them if they're present in extraced .psd1)
        Added ValidateSet on scopes; trailing gmo -list on the install; expanded verbose support
    * 2:45 PM 1/11/2024 add: code to rebuild completely broken psd1 manifest (where inbound is incomplete/untested);
         add suitable echos for missing inbound params;
         trailing echo for install location ;
         PCX mod has clashing Expand-Archive cmdlet: module-qualify the call ;
         -ProjectUri was obviously intended to be typed [uri], it checks for a non-existant .OriginalString, so strongly typed [uri];
         Clearly v1.6.0 includes -scope, but it also assumes PScore (wrong mod path for WindowsPS use), add testing for variant;
         added CBH, also needs docs that it *defaults* to AllUsers\Modules install
    * 11/27/22 v1.6.0 dfinke latest posted version (source for fork)
    .DESCRIPTION
    Install-ModuleFromGitHub.ps1 - Adds cmdlets for direct installing mods from GitHub. Works similar to Install-Module. It streamlines the multi-step process of downloading the zip from GitHub, unblocking it, unzipping it and copying it to a well known module directory. It also checks for a ‘psd1’ file, cracks is open and uses the ModuleVersion to create a directory for it to copy the bits to.

    Adds cmdlets for direct installing mods from GitHub. Works similar to Install-Module. It streamlines the multi-step process of downloading the zip from GitHub, unblocking it, unzipping it and copying it to a well known module directory. It also checks for a ‘psd1’ file, cracks is open and uses the ModuleVersion to create a directory for it to copy the bits to.

    Dfinke's blog post: https://dfinke.github.io/powershell/2016/11/21/Quickly-Install-PowerShell-Modules-from-GitHub.html

    Syntax: 
    Install-ModuleFromGitHub [[-GitHubRepo] <Object>] [[-Branch] <Object>] [[-ProjectUri] <Object>]
        [[-DestinationPath] <Object>] [[-SSOToken] <Object>] [[-moduleName] <Object>]  [<CommonParameters>]

    .PARAMETER GitHubRepo
    Source as string in format: [username/reponame][-githubrepo dfinke/ImportExcel]
    .PARAMETER Branch
    Repo target branch (defaults to Master)[-Branch Fix]
    .PARAMETER ProjectUri
    Optional full repo URI, to be parsed to determine user/Repo and branch (alt to use of GitHubRepo)
    .PARAMETER DestinationPath
    Destination file system path (defaults to below AllUsers below Modules subdir)
    .PARAMETER SSOToken
    Authentication Token
    .PARAMETER moduleName
    Explicit module name (vs parsing & using the RepoName as the Modulename)[-moduleName 'somemodule']
    .PARAMETER scope
    Target Scope (AllUsers|CurrentUser, defaults to AllUsers)[-scope CurrentUser]
    .INPUTS
    None. Does not accepted piped input.(.NET types, can add description)
    .OUTPUTS
    None. Returns no objects or output (.NET types)
    System.Boolean
    [| get-member the output to see what .NET obj TypeName is returned, to use here]
    .EXAMPLE
    PS> Install-ModuleFromGitHub -GitHubRepo dfinke/ImportExcel ; 
    Install non-PsG direct from GH: (spec the repo )
    .EXAMPLE
    PS> Install-ModuleFromGitHub -GitHubRepo dfinke/NameIT ; 
    Install non-PsG direct from GH: (spec the repo )
    .EXAMPLE
    PS> Install-ModuleFromGitHub -GitHubRepo rossobianero/NupkgDownloader 
    Install non-PsG direct from GH: (spec the repo )
    .EXAMPLE
    PS> Install-ModuleFromGitHub -GitHubRepo dfinke/ImportExcel -Branch NewChartType ; 
    Install non-PsG specific branch on repo:
    .EXAMPLE
    PS> Install-ModuleFromGitHub -GitHubRepo tostka/PsGist -Branch FixAuth ; 
    Install non-PsG specific branch on repo:
    .EXAMPLE
    PS> Install-ModuleFromGitHub -ProjectUri https://github.com/rossobianero/NupkgDownloader -Scope CurrentUser -verbose ;
    Install via ProjectUri into CurrentUser scope, with verbose output
    .EXAMPLE
    PS> Install-ModuleFromGitHub -ProjectUri https://github.com/rossobianero/NupkgDownloader -Scope CurrentUser -AssertVersion '1.2.3' -verbose ;
    Install via ProjectUri into CurrentUser scope, with verbose output

    .LINK
    https://dfinke.github.io/powershell/2016/11/21/Quickly-Install-PowerShell-Modules-from-GitHub.html
    .LINK
    https://github.com/tostka/InstallModuleFromGitHub
    .LINK
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position=0,Mandatory=$false,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Source as string in format: [username/reponame][-githubrepo dfinke/ImportExcel]")]
            $GitHubRepo,
        [Parameter(HelpMessage="Repo target branch (defaults to Master)[-Branch Fix]")]
            $Branch = "master",
        [Parameter(ValueFromPipelineByPropertyName=$true,HelpMessage="Optional full repo URI, to be parsed to determine user/Repo and branch (alt to use of GitHubRepo)")]
            [uri]$ProjectUri,
        [Parameter(HelpMessage="Destination file system path (defaults to below AllUsers below Modules subdir)")]
            $DestinationPath,
        [Parameter(HelpMessage="Authentication Token")]
            $SSOToken,
        [Parameter(Mandatory=$False,HelpMessage="Explicit module name (vs parsing & using the RepoName as the Modulename)[-moduleName 'somemodule']")]
            $moduleName,
        [Parameter(Mandatory=$False,HelpMessage="Target Scope (AllUsers|CurrentUser, defaults to AllUsers)[-scope CurrentUser]")]
            [ValidateSet("AllUsers","CurrentUser")]
            $Scope = 'AllUsers',
        [Parameter(HelpMessage="Optional Explicit 3-digit ModuleVersion specification (Used when inbound .psd1 lacks proper ModuleVersion: permits forcing a specific new value - defaults to 0.5.0)[-Version 2.0.3]")]
            [version]$AssertVersion
    )

    Process {
        if($PSBoundParameters.ContainsKey("ProjectUri")) {
            $GitHubRepo = $null
            if($ProjectUri.OriginalString.StartsWith("https://github.com")) {
                $GitHubRepo = $ProjectUri.AbsolutePath
            } else {
                $name=$ProjectUri.LocalPath.split('/')[-1]
                Write-Host -ForegroundColor Red ("Module [{0}]: not installed, it is not hosted on GitHub " -f $name)
            }
        }

        if($GitHubRepo) {
                Write-Verbose ("[$(Get-Date)] Retrieving {0} {1}" -f $GitHubRepo, $Branch)

                $url = "https://api.github.com/repos/{0}/zipball/{1}" -f $GitHubRepo, $Branch
                # 2:55 PM 1/11/2024 failing, retry public: https://github.com/rossobianero/NupkgDownloader/zipball/master
                $url2 = "https://github.com/{0}/zipball/{1}" -f $GitHubRepo, $Branch

                if ($moduleName) {
                    $targetModuleName = $moduleName
                } else {
                    $targetModuleName=$GitHubRepo.split('/')[-1]
                }
                Write-Debug "targetModuleName: $targetModuleName"

                $tmpDir = [System.IO.Path]::GetTempPath()

                $OutFile = Join-Path -Path $tmpDir -ChildPath "$($targetModuleName).zip"
                Write-Debug "OutFile: $OutFile"

                if ($SSOToken) {$headers = @{"Authorization" = "token $SSOToken" }}

                #enable TLS1.2 encryption
                if (-not ($IsLinux -or $IsMacOS)) {
                    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                }
                $Exit = 0 ; $Retries = 2 ;
                Do {
                    TRY{
                        Invoke-RestMethod $url -OutFile $OutFile -Headers $headers -ErrorAction STOP -ErrorVariable errIRM
                        $Exit = $Retries ;
                    } CATCH {
                        #$_.Exception.Message ;
                        $ErrTrapd=$Error[0]
                        $Exit ++ ;
                        $smsg = $vmsg = $null ; 
                        $smsg += "Try #: $($Exit)" ;

                        if ($Exit -eq $Retries) {
                            $smsg += "Unable to exec cmd!" ;
                            throw $smsg ;
                            BREAK ; 
                        } ;
                        
                        if($ErrTrapd){
                            $smsg = "`n$(($ErrTrapd | fl * -Force|out-string).trim())" ;
                        } else { 
                            $smsg += "`nfailed to download:$($url)!" ;
                        } ; 
                        if($errIRM){
                            $smsg += "`nResponse.StatusCode:$($errIRM.ErrorRecord.Exception.Response.StatusCode)!" ;
                            $smsg += "`nResponse.StatusCode number:$([int]$errIRM.ErrorRecord.Exception.Response.StatusCode)!" ;
                            $vmsg = "`nResponse.Headers:`n$(($errIRM.ErrorRecord.Exception.Response.Headers -join ', '|out-string).trim())" ; 
                            $vmsg += "`n$(($errIRM | fl * -Force|out-string).trim())" ;
                        } ; 
                        write-warning $smsg ;
                        if($vmsg){ write-verbose $vmsg} ; 
                        write-host -foregroundcolor yellow "Retrying using alt url:`n $($url2)" ;
                        $url = $url2 ; 
                    } ; 
                } Until ($Exit -eq $Retries) ; 
                if (-not ([System.Environment]::OSVersion.Platform -eq "Unix")) {
                  Unblock-File $OutFile
                }

                $fileHash = $(Get-FileHash -Path $OutFile).hash
                $tmpDir = "$tmpDir/$fileHash"

                # Pscx has a clashing Expand-Archive without the -dest param, module-qualify to the target module
                Microsoft.PowerShell.Archive\Expand-Archive -Path $OutFile -DestinationPath $tmpDir -Force
                
                $unzippedArchive = get-childItem "$tmpDir"
                Write-Debug "targetModule: $targetModule"

                if ([System.Environment]::OSVersion.Platform -eq "Unix") {
                    if ($Scope -eq "CurrentUser") {
                        $dest = Join-Path -Path $HOME -ChildPath ".local/share/powershell/Modules"
                    } else {
                        $dest = "/usr/local/share/powershell/Modules"
                    }
                }

                else {
                    if ($Scope -eq "CurrentUser") {
                        $scopedPath = $HOME
                        if (($PSVersionTable.PSEdition -eq 'Desktop') -OR ($IsCoreCLR -AND $IsWindows)) {
                            $scopedChildPath = "\Documents\WindowsPowerShell\Modules"
                        } elseif ( ($IsCoreCLR -AND $IsWindows)) {
                            $scopedChildPath = "\Documents\PowerShell\Modules"
                        } 
                    } else {
                        $scopedPath = $env:ProgramFiles
                        if (($PSVersionTable.PSEdition -eq 'Desktop') -OR ($IsCoreCLR -AND $IsWindows)) {
                            $scopedChildPath = "\WindowsPowerShell\Modules"
                        } elseif ( ($IsCoreCLR -AND $IsWindows)) {
                            $scopedChildPath = "\PowerShell\Modules"
                        } 
                    }
                  $dest = Join-Path -Path $scopedPath -ChildPath $scopedChildPath
                }

                if($DestinationPath) {
                    $dest = $DestinationPath
                }
                $dest = Join-Path -Path $dest -ChildPath $targetModuleName
                if ([System.Environment]::OSVersion.Platform -eq "Unix") {
                    $psd1 = Get-ChildItem (Join-Path -Path $unzippedArchive -ChildPath *) -Include *.psd1 -Recurse
                } else {
                    $psd1 = Get-ChildItem (Join-Path -Path $tmpDir -ChildPath $unzippedArchive.Name) -Include *.psd1 -Recurse
                } 

                $sourcePath = $unzippedArchive.FullName
                
                if($psd1) {
                    # test, some mod psd1s don't have required ModuleVersion spec'd, fix on the fly...
                    # better: run full test-ModuleManifest, trigger rebuild based on what it does have, if it won't pass for any reason:

                    TRY {
                        $psd1Profile = Test-ModuleManifest -path $psd1.fullname -errorVariable ttmm_Err -WarningVariable ttmm_Wrn -InformationVariable ttmm_Inf -ErrorAction STOP ;
                    } CATCH {
                        $ErrTrapd=$Error[0] ;
                        if($ErrTrapd){
                            $smsg = "`n$(($ErrTrapd | fl * -Force|out-string).trim())" ;
                            write-warning $smsg ;
                        } ; 
                        if($ttmm_Err){
                            $smsg = "`nFOUND `$ttmm_Err: test-ModuleManifest HAD ERRORS!" ;
                            if ($logging) { Write-Log -LogContent $smsg -Path $logfile -useHost -Level WARN -Indent}
                            else{ write-WARNING $smsg } ;
                            foreach($errExcpt in $ttmm_Err.Exception){
                                $smsg = "`n$($errExcpt)" ;
                                write-WARNING $smsg  ;
                            } ;
                            
                            <# Building a new intact ModuleManifest .psd1 file:
                            Provisos: 
                            - Update-ModuleManifest -Path $psd1.FullName -ModuleVersion $defaultVersion -verbose ; 
                                => You can't update if existing is missing ModuleVersion: Need to new-ModuleManifest constructed off of what's *in* the psd1
                            - Test-ModuleManifest likewise throws up if missing ModuleVersion, use Import-PowershellDataFile to pull in existing content
                            
                            # Req'd new-ModuleManifest parameters: Only ModuleVersion is explicitly required in the .psd1:

                            [New-ModuleManifest (Microsoft.PowerShell.Core) - PowerShell | Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/new-modulemanifest?view=powershell-5.1)
                            -ModuleVersion, isn't [a] required [parameter], but a ModuleVersion key is required in the manifest. If you omit this parameter, New-ModuleManifest creates a ModuleVersion key with a value of 1.0.
                            If you are planning to publish your module in the PowerShell Gallery, the 
                                manifest must contain values for certain properties. For more information, see 
                                Required metadata for items published to the PowerShell Gallery in the Gallery documentation:
                                [Creating and publishing an item - PowerShell | Microsoft Learn](https://learn.microsoft.com/en-us/powershell/gallery/how-to/publishing-packages/publishing-a-package?view=powershellget-3.x#required-metadata-for-items-published-to-the-powershell-gallery)
                                
                                => Odds are, if you're installing a 3rd party's github module, you aren't going to be PSG publishing it :'D So we'll skip populating the PSG-mandated metadata fields
                                    If you are planning to publish your module in the PowerShell Gallery, the
                                    manifest must contain values for certain properties. For more information, see
                                    Required metadata for items published to the PowerShell Gallery in the Gallery documentation.
                                        - ModuleName
                                        - ModuleVersion
                                        - Author
                                        - Description
                                        - ProjectURI
                                        - Tags
                            #>
                            #if($ModuleVersion=(Get-Content -Raw $psd1.FullName | Invoke-Expression).ModuleVersion){ # nothing to parse if it's missing completely
                            # pull what's in the existing in, for transplanting into new
                            $psdinfo = Import-PowerShellDataFile -Path $psd1.FullName -EA STOP ; 
                            if($psdinfo.ModuleVersion){
                                write-verbose "detected a required ModuleVersion key: $($ModuleVersion)" ; 
                            } else { 
                                if($AssertVersion){ 
                                    $defaultVersion = "$($AssertVersion.major).$($AssertVersion.minor).$($AssertVersion.Build)" ; 
                                } else { $defaultVersion = '0.5.0' ; } ;
                                write-host "No psd1.ModuleVersion found: Asserting arbitrary $($defaultVersion)" ; 
                            } ; 
                            $pltNMM=[ordered]@{
                                Path = $psd1.FullName ; 
                                Copyright = $null ;
                                #Description = $null ;
                                PrivateData = $null ;
                                CompanyName = $null ;
                                GUID = $null ;
                                Author = $null ;
                                FunctionsToExport = $null ;
                                VariablesToExport = $null ;
                                RootModule = $null ;
                                AliasesToExport = $null ;
                                CmdletsToExport = $null ;
                                ModuleVersion = $null ;
                                #ProjectUri = $null ;
                                #Tags = $null ;
                                ErrorAction = 'STOP' ; 
                                Verbose = $true ;                                
                            } ;
                            # loop out whatever's in there and assign to the splat:
                            $psdinfo.GetEnumerator() |foreach {
                                if($pltNMM.contains($_.key)){
                                    $pltNMM[$_.key] = $_.value 
                                } else {
                                    $pltNMM.add($_.key,$_.value ) ; 
                                } 
                            }
                            # coerce a default ModuleVersion, if none spec'd
                            if($pltNMM.ModuleVersion -eq $null){$ModuleVersion = $pltNMM.ModuleVersion = $defaultVersion} ; 
                            $smsg = "REBUILDING FRESH OVER DAMAGED/INCOMPLETE PSD1:`nnew-ModuleManifest w`n$(($pltNMM|out-string).trim())" ; 
                            write-host -foregroundcolor Yellow $smsg ;
                            TRY{
                                new-ModuleManifest  @pltNMM
                                # overwrites even sketchy half populated existing .psd1's with fully populated (or throws up with a fixable error)
                            } CATCH {
                                $ErrTrapd=$Error[0] ;
                                $smsg = "`n$(($ErrTrapd | fl * -Force|out-string).trim())" ;
                                write-warning $smsg ;
                                throw $smsg ;
                                break ;
                            } ; 
                        } else {
                            $smsg = "(no `$ttmm_Err: test-ModuleManifest had no errors)" ;
                            write-verbose $smsg ;
                        } ; 
                    } ; 
                
                    $dest = Join-Path -Path $dest -ChildPath $ModuleVersion
                    $null = New-Item -ItemType directory -Path $dest -Force
                    $sourcePath = $psd1.DirectoryName
                } else {
                    $smsg = "Unable to locate a PSD1 file!:Get-ChildItem (Join-Path -Path $($tmpDir) -ChildPath $($unzippedArchive.Name)) -Include *.psd1 -Recurse" ; 
                    write-warning $smsg ;
                    throw $smsg ;
                    Break ; 
                } 

                TRY{
                    if ([System.Environment]::OSVersion.Platform -eq "Unix") {
                        $null = Copy-Item "$(Join-Path -Path $unzippedArchive -ChildPath *)" $dest -Force -Recurse -verbose:$($VerbosePreference -eq "Continue") 
                    } else {
                        $null = Copy-Item "$sourcePath\*" $dest -Force -Recurse -ErrorAction Stop -verbose:$($VerbosePreference -eq "Continue")
                    }
                } CATCH {
                    $ErrTrapd=$Error[0] ;
                    $smsg = "`n$(($ErrTrapd | fl * -Force|out-string).trim())" ;
                    write-warning "$((get-date).ToString('HH:mm:ss')):$($smsg)" ;
                } ; 

                $smsg = "Newly created module installed to:`n$($dest)"
                write-host -foregroundcolor green $smsg  ; 
                TRY{
                    $smsg = "get-module -name $($targetModuleName) -ListAvailable  `n$((get-module -name $targetModuleName -ListAvailable -erroraction STOP |out-string).trim())" ; 
                    write-host -foregroundcolor green $smsg ;
                } CATCH {
                    $ErrTrapd=$Error[0] ;
                    $smsg = "`n$(($ErrTrapd | fl * -Force|out-string).trim())" ;
                    write-warning "$((get-date).ToString('HH:mm:ss')):$($smsg)" ;
                } ; 

        } else {
            $smsg = "No -GitHubRepo specified!`nplease specify in username\reponame format" ; 
            write-warning $smsg ;
            throw $smsg ;
        } ; 
    }
}

# Install-ModuleFromGitHub dfinke/nameit
# Install-ModuleFromGitHub dfinke/nameit TestBranch
